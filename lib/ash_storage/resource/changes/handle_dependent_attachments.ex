defmodule AshStorage.Resource.Changes.HandleDependentAttachments do
  @moduledoc false
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.action.soft? do
      changeset
    else
      changeset
      |> Ash.Changeset.after_action(&destroy_records/2)
      |> Ash.Changeset.after_transaction(&delete_files/2)
    end
  end

  # Inside transaction: destroy attachment/blob records, collect keys to purge
  defp destroy_records(_changeset, record) do
    resource = record.__struct__
    attachments = AshStorage.Resource.Info.attachments(resource)

    case collect_and_destroy(record, resource, attachments) do
      {:ok, keys_to_purge} ->
        {:ok, Ash.Resource.put_metadata(record, :__ash_storage_keys_to_purge__, keys_to_purge)}

      {:error, error} ->
        {:error, error}
    end
  end

  defp collect_and_destroy(record, _resource, attachments) do
    Enum.reduce_while(attachments, {:ok, []}, fn attachment_def, {:ok, keys_acc} ->
      case attachment_def.dependent do
        :purge ->
          case AshStorage.Operations.destroy_attachment_and_blob_records(
                 record,
                 attachment_def.name
               ) do
            {:ok, purge_keys} -> {:cont, {:ok, keys_acc ++ purge_keys}}
            {:error, error} -> {:halt, {:error, error}}
          end

        :detach ->
          case AshStorage.Operations.detach_all(record, attachment_def.name) do
            {:ok, _} -> {:cont, {:ok, keys_acc}}
            {:error, error} -> {:halt, {:error, error}}
          end

        false ->
          {:cont, {:ok, keys_acc}}
      end
    end)
  end

  # Outside transaction: delete files from storage (only on success)
  defp delete_files(_changeset, {:ok, record}) do
    keys_to_purge = record.__metadata__[:__ash_storage_keys_to_purge__] || []

    Enum.each(keys_to_purge, fn {service_mod, service_opts, key} ->
      AshStorage.Operations.delete_from_service(service_mod, service_opts, key)
    end)

    {:ok, record}
  end

  defp delete_files(_changeset, {:error, error}), do: {:error, error}
end
