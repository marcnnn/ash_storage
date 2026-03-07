defmodule AshStorage.Operations do
  @moduledoc """
  Core operations for managing file attachments.

  These functions handle the lifecycle of attachments: uploading files,
  creating blob and attachment records, detaching, and purging.
  """

  require Ash.Query

  alias AshStorage.Resource.Info
  alias AshStorage.Service.Context

  @doc """
  Attach a file to a record.

  Uploads the file to the storage service, creates a blob record, and creates
  an attachment record linking the blob to the record.

  The `io` argument can be binary data, iodata, a `File.Stream`, or an
  `Ash.Type.File` (which also accepts `Plug.Upload` and other sources via
  the `Ash.Type.File.Source` protocol).

  For `has_one_attached`, any existing attachment with the same name is replaced
  (the old blob and file are purged).

  For `has_many_attached`, the new attachment is appended.

  ## Options

  - `:filename` - (required) the original filename
  - `:content_type` - MIME type of the file (default: `"application/octet-stream"`)
  - `:metadata` - additional metadata map to store on the blob
  - `:actor` - the actor performing the operation
  - `:tenant` - the tenant

  ## Examples

      AshStorage.Operations.attach(post, :cover_image, file_data,
        filename: "photo.jpg",
        content_type: "image/jpeg"
      )
  """
  def attach(record, attachment_name, io, opts \\ []) do
    resource = record.__struct__

    with {:ok, attachment_def} <- Info.attachment(resource, attachment_name),
         {:ok, {service_mod, service_opts}} <- resolve_service(resource, attachment_def),
         ctx = build_context(service_opts, resource, attachment_def, opts),
         {:ok, blob} <- upload_and_create_blob(resource, service_mod, ctx, io, opts),
         {:ok, _} <- maybe_replace_existing(record, attachment_def, service_mod, ctx),
         {:ok, attachment} <- create_attachment(record, attachment_def, blob) do
      {:ok, %{blob: blob, attachment: attachment}}
    end
  end

  @doc """
  Prepare a direct upload: create a blob record and return a presigned URL.

  The client can then upload directly to the storage service (e.g. S3) without
  streaming through the server. After the client finishes uploading, call
  `confirm_direct_upload/4` to create the attachment record.

  ## Options

  - `:filename` - (required) the original filename
  - `:content_type` - MIME type (default: `"application/octet-stream"`)
  - `:byte_size` - file size in bytes (required for some services)
  - `:checksum` - base64-encoded MD5 checksum (optional, used for integrity verification)
  - `:metadata` - additional metadata map to store on the blob
  - `:actor` - the actor performing the operation
  - `:tenant` - the tenant

  ## Returns

  Returns `{:ok, upload_info}` where `upload_info` is the map from the
  service's `direct_upload/2` callback with an added `:blob` key.

  For presigned PUT: `%{blob: blob, url: "https://...", method: :put}`
  For presigned POST: `%{blob: blob, url: "https://...", method: :post, fields: [...]}`
  """
  def prepare_direct_upload(resource, attachment_name, opts \\ []) do
    with {:ok, attachment_def} <- Info.attachment(resource, attachment_name),
         {:ok, {service_mod, service_opts}} <- resolve_service(resource, attachment_def) do
      ctx = build_context(service_opts, resource, attachment_def, opts)

      filename = Keyword.fetch!(opts, :filename)
      content_type = Keyword.get(opts, :content_type, "application/octet-stream")
      byte_size = Keyword.get(opts, :byte_size, 0)
      checksum = Keyword.get(opts, :checksum, "")
      metadata = Keyword.get(opts, :metadata, %{})

      key = AshStorage.generate_key()
      blob_resource = Info.storage_blob_resource!(resource)

      with {:ok, blob} <-
             Ash.create(
               blob_resource,
               %{
                 key: key,
                 filename: filename,
                 content_type: content_type,
                 byte_size: byte_size,
                 checksum: checksum,
                 service_name: service_mod,
                 metadata: metadata
               },
               action: :create
             ),
           {:ok, upload_info} <- service_mod.direct_upload(key, ctx) do
        {:ok, Map.put(upload_info, :blob, blob)}
      end
    end
  end

  @doc """
  Confirm a direct upload and attach the blob to a record.

  Call this after the client has finished uploading directly to the storage
  service. This creates the attachment record linking the blob to the record.

  For `has_one_attached`, any existing attachment is replaced (old blob and file
  are purged). For `has_many_attached`, the blob is appended.

  ## Options

  - `:actor` - the actor performing the operation
  - `:tenant` - the tenant
  """
  def confirm_direct_upload(record, attachment_name, blob_id, opts \\ []) do
    resource = record.__struct__

    with {:ok, attachment_def} <- Info.attachment(resource, attachment_name),
         {:ok, {service_mod, service_opts}} <- resolve_service(resource, attachment_def),
         ctx = build_context(service_opts, resource, attachment_def, opts),
         {:ok, blob} <- fetch_blob(resource, blob_id),
         {:ok, _} <- maybe_replace_existing(record, attachment_def, service_mod, ctx),
         {:ok, attachment} <- create_attachment(record, attachment_def, blob) do
      {:ok, %{blob: blob, attachment: attachment}}
    end
  end

  @doc """
  Detach an attachment from a record without deleting the blob or file.

  For `has_one_attached`, removes the single attachment.
  For `has_many_attached`, removes the attachment matching the given blob ID.

  ## Options

  - `:blob_id` - (required for `has_many_attached`) which attachment to detach
  """
  def detach(record, attachment_name, opts \\ []) do
    resource = record.__struct__

    with {:ok, attachment_def} <- Info.attachment(resource, attachment_name),
         {:ok, attachments} <- find_attachments(record, attachment_def),
         {:ok, to_detach} <- select_for_detach(attachments, attachment_def, opts) do
      destroy_attachment_records(to_detach)
    end
  end

  @doc """
  Detach all attachments for a given name from a record.

  Unlike `detach/3`, this does not require a `:blob_id` for `has_many_attached`.
  """
  def detach_all(record, attachment_name) do
    resource = record.__struct__

    with {:ok, attachment_def} <- Info.attachment(resource, attachment_name),
         {:ok, attachments} <- find_attachments(record, attachment_def) do
      destroy_attachment_records(attachments)
    end
  end

  @doc """
  Purge an attachment: destroy the attachment record, blob record, and file from storage.

  For `has_one_attached`, purges the single attachment.
  For `has_many_attached`, purges the attachment matching the given blob ID,
  or all attachments if `:all` is passed.

  ## Options

  - `:blob_id` - (required for `has_many_attached` unless `:all` is true) which attachment to purge
  - `:all` - purge all attachments for this name (default: `false`)
  - `:actor` - the actor performing the operation
  - `:tenant` - the tenant
  """
  def purge(record, attachment_name, opts \\ []) do
    resource = record.__struct__

    with {:ok, attachment_def} <- Info.attachment(resource, attachment_name),
         {:ok, attachments} <- find_attachments(record, attachment_def),
         {:ok, to_purge} <- select_for_purge(attachments, attachment_def, opts),
         {:ok, {service_mod, service_opts}} <- resolve_service(resource, attachment_def) do
      ctx = build_context(service_opts, resource, attachment_def, opts)
      purge_attachments(to_purge, service_mod, ctx)
    end
  end

  @doc """
  Destroy attachment and blob records for a given attachment name, without deleting
  files from storage. Returns the list of `{service_mod, context, key}` tuples
  for deferred file deletion.

  This is used by the dependent destroy change to separate DB work (inside transaction)
  from file deletion (outside transaction or async).
  """
  def destroy_attachment_and_blob_records(record, attachment_name, opts \\ []) do
    resource = record.__struct__

    with {:ok, attachment_def} <- Info.attachment(resource, attachment_name),
         {:ok, attachments} <- find_attachments(record, attachment_def),
         {:ok, {service_mod, service_opts}} <- resolve_service(resource, attachment_def) do
      ctx = build_context(service_opts, resource, attachment_def, opts)

      Enum.reduce_while(attachments, {:ok, []}, fn att, {:ok, keys_acc} ->
        blob = att.blob

        with {:ok, _} <- Ash.destroy(att, action: :destroy, return_destroyed?: true),
             {:ok, _} <- Ash.destroy(blob, action: :destroy, return_destroyed?: true) do
          {:cont, {:ok, [{service_mod, ctx, blob.key} | keys_acc]}}
        else
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  @doc """
  Attach multiple files to multiple records in bulk.

  Takes a list of `{record, attachment_name, io, opts}` tuples and processes them
  efficiently, using bulk upload when the service supports it.

  Returns a list of `{:ok, %{blob: blob, attachment: attachment}}` or `{:error, reason}`
  results in the same order as the input.
  """
  def attach_many(items) do
    items
    |> Enum.with_index()
    |> Enum.group_by(fn {{record, attachment_name, _io, _opts}, _idx} ->
      {record.__struct__, attachment_name}
    end)
    |> Enum.flat_map(fn {{resource, attachment_name}, indexed_items} ->
      case Info.attachment(resource, attachment_name) do
        {:ok, attachment_def} ->
          case resolve_service(resource, attachment_def) do
            {:ok, {service_mod, service_opts}} ->
              # Use opts from first item for actor/tenant context
              {_record, _name, _io, first_opts} = elem(hd(indexed_items), 0)
              ctx = build_context(service_opts, resource, attachment_def, first_opts)

              attach_many_for_group(
                indexed_items,
                resource,
                attachment_def,
                service_mod,
                ctx
              )

            {:error, reason} ->
              Enum.map(indexed_items, fn {_item, idx} -> {idx, {:error, reason}} end)
          end

        :error ->
          Enum.map(indexed_items, fn {_item, idx} -> {idx, :error} end)
      end
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Delete a file from a storage service.
  """
  def delete_from_service(service_mod, %Context{} = ctx, key) do
    service_mod.delete(key, ctx)
  end

  # -- Private helpers --

  defp build_context(service_opts, resource, attachment_def, opts) do
    Context.new(service_opts,
      resource: resource,
      attachment: attachment_def,
      actor: Keyword.get(opts, :actor),
      tenant: Keyword.get(opts, :tenant)
    )
  end

  defp fetch_blob(resource, blob_id) do
    blob_resource = Info.storage_blob_resource!(resource)

    case Ash.get(blob_resource, blob_id) do
      {:ok, blob} -> {:ok, blob}
      {:error, _} -> {:error, :blob_not_found}
    end
  end

  defp resolve_service(resource, attachment_def) do
    case Info.service_for_attachment(resource, attachment_def) do
      {:ok, service} -> {:ok, service}
      :error -> {:error, :no_service_configured}
    end
  end

  defp upload_and_create_blob(resource, service_mod, ctx, io, opts) do
    filename = Keyword.fetch!(opts, :filename)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    metadata = Keyword.get(opts, :metadata, %{})

    data = read_io(io)
    key = AshStorage.generate_key()
    checksum = :crypto.hash(:md5, data) |> Base.encode64()
    byte_size = byte_size(data)

    with :ok <- service_mod.upload(key, data, ctx) do
      blob_resource = Info.storage_blob_resource!(resource)

      Ash.create(
        blob_resource,
        %{
          key: key,
          filename: filename,
          content_type: content_type,
          byte_size: byte_size,
          checksum: checksum,
          service_name: service_mod,
          metadata: metadata
        },
        action: :create
      )
    end
  end

  defp read_io(%Ash.Type.File{} = file) do
    {:ok, device} = Ash.Type.File.open(file, [:read, :binary])
    data = IO.binread(device, :eof)
    File.close(device)
    data
  end

  defp read_io(%File.Stream{} = stream), do: Enum.into(stream, <<>>, &IO.iodata_to_binary/1)
  defp read_io(data) when is_binary(data), do: data
  defp read_io(data) when is_list(data), do: IO.iodata_to_binary(data)

  defp maybe_replace_existing(record, %{type: :one} = attachment_def, service_mod, ctx) do
    case find_attachments(record, attachment_def) do
      {:ok, []} ->
        {:ok, :noop}

      {:ok, existing} ->
        purge_attachments(existing, service_mod, ctx)
    end
  end

  defp maybe_replace_existing(_record, %{type: :many}, _service_mod, _ctx), do: {:ok, :noop}

  # sobelow_skip ["DOS.BinToAtom"]
  defp create_attachment(record, attachment_def, blob) do
    resource = record.__struct__
    attachment_resource = Info.storage_attachment_resource!(resource)

    record_id = Map.get(record, :id) |> to_string()

    belongs_to_resources =
      Spark.Dsl.Extension.get_entities(attachment_resource, [:attachment])

    params =
      if belongs_to_resources == [] do
        %{
          name: to_string(attachment_def.name),
          record_type: to_string(resource),
          record_id: record_id,
          blob_id: blob.id
        }
      else
        parent_rel =
          Enum.find(belongs_to_resources, fn bt ->
            bt.resource == resource
          end)

        if parent_rel do
          fk_attr = :"#{parent_rel.name}_id"

          Map.new([
            {:name, to_string(attachment_def.name)},
            {fk_attr, record_id},
            {:blob_id, blob.id}
          ])
        else
          %{
            name: to_string(attachment_def.name),
            record_type: to_string(resource),
            record_id: record_id,
            blob_id: blob.id
          }
        end
      end

    Ash.create(attachment_resource, params, action: :create)
  end

  # sobelow_skip ["DOS.BinToAtom"]
  defp find_attachments(record, attachment_def) do
    resource = record.__struct__
    attachment_resource = Info.storage_attachment_resource!(resource)
    record_id = Map.get(record, :id) |> to_string()

    belongs_to_resources =
      Spark.Dsl.Extension.get_entities(attachment_resource, [:attachment])

    parent_rel =
      Enum.find(belongs_to_resources, fn bt ->
        bt.resource == resource
      end)

    filter =
      if parent_rel do
        [{:name, to_string(attachment_def.name)}, {:"#{parent_rel.name}_id", record_id}]
      else
        [
          name: to_string(attachment_def.name),
          record_type: to_string(resource),
          record_id: record_id
        ]
      end

    attachment_resource
    |> Ash.Query.filter(^filter)
    |> Ash.Query.load(:blob)
    |> Ash.read()
  end

  defp select_for_detach(attachments, %{type: :one}, _opts), do: {:ok, attachments}

  defp select_for_detach(attachments, %{type: :many}, opts) do
    case Keyword.fetch(opts, :blob_id) do
      {:ok, blob_id} ->
        {:ok, Enum.filter(attachments, &(&1.blob_id == blob_id))}

      :error ->
        {:error, :blob_id_required_for_has_many}
    end
  end

  defp select_for_purge(attachments, %{type: :one}, _opts), do: {:ok, attachments}

  defp select_for_purge(attachments, %{type: :many}, opts) do
    if Keyword.get(opts, :all, false) do
      {:ok, attachments}
    else
      case Keyword.fetch(opts, :blob_id) do
        {:ok, blob_id} ->
          {:ok, Enum.filter(attachments, &(&1.blob_id == blob_id))}

        :error ->
          {:error, :blob_id_required_for_has_many}
      end
    end
  end

  defp destroy_attachment_records(attachments) do
    Enum.reduce_while(attachments, {:ok, []}, fn att, {:ok, acc} ->
      case Ash.destroy(att, action: :destroy, return_destroyed?: true) do
        {:ok, destroyed} -> {:cont, {:ok, [destroyed | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp purge_attachments(attachments, service_mod, ctx) do
    Enum.reduce_while(attachments, {:ok, []}, fn att, {:ok, acc} ->
      blob = att.blob

      with :ok <- service_mod.delete(blob.key, ctx),
           {:ok, _} <- Ash.destroy(att, action: :destroy, return_destroyed?: true),
           {:ok, _} <- Ash.destroy(blob, action: :destroy, return_destroyed?: true) do
        {:cont, {:ok, [att | acc]}}
      else
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp attach_many_for_group(indexed_items, resource, attachment_def, service_mod, ctx) do
    # Prepare all uploads: read data, generate keys, compute checksums
    prepared =
      Enum.map(indexed_items, fn {{record, _name, io, opts}, idx} ->
        filename = Keyword.fetch!(opts, :filename)
        content_type = Keyword.get(opts, :content_type, "application/octet-stream")
        metadata = Keyword.get(opts, :metadata, %{})
        data = read_io(io)
        key = AshStorage.generate_key()
        checksum = :crypto.hash(:md5, data) |> Base.encode64()
        byte_size = byte_size(data)

        {idx, record, key, data,
         %{
           filename: filename,
           content_type: content_type,
           metadata: metadata,
           checksum: checksum,
           byte_size: byte_size
         }}
      end)

    # Bulk upload if supported, otherwise individual uploads
    upload_result =
      if function_exported?(service_mod, :upload_many, 2) do
        upload_entries =
          Enum.map(prepared, fn {_idx, _record, key, data, _meta} ->
            {key, data}
          end)

        service_mod.upload_many(upload_entries, ctx)
      else
        Enum.reduce_while(prepared, :ok, fn {_idx, _record, key, data, _meta}, :ok ->
          case service_mod.upload(key, data, ctx) do
            :ok -> {:cont, :ok}
            {:error, _} = err -> {:halt, err}
          end
        end)
      end

    case upload_result do
      :ok ->
        Enum.map(prepared, fn {idx, record, key, _data, meta} ->
          blob_resource = Info.storage_blob_resource!(resource)

          result =
            with {:ok, _} <- maybe_replace_existing(record, attachment_def, service_mod, ctx),
                 {:ok, blob} <-
                   Ash.create(
                     blob_resource,
                     %{
                       key: key,
                       filename: meta.filename,
                       content_type: meta.content_type,
                       byte_size: meta.byte_size,
                       checksum: meta.checksum,
                       service_name: service_mod,
                       metadata: meta.metadata
                     },
                     action: :create
                   ),
                 {:ok, attachment} <- create_attachment(record, attachment_def, blob) do
              {:ok, %{blob: blob, attachment: attachment}}
            end

          {idx, result}
        end)

      {:error, reason} ->
        Enum.map(prepared, fn {idx, _record, _key, _data, _meta} ->
          {idx, {:error, reason}}
        end)
    end
  end
end
