defmodule Demo.Attachment do
  @moduledoc false
  use Ash.Resource,
    domain: Demo.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table "storage_attachments"
    repo(Demo.Repo)

    references do
      reference :post, on_delete: :nilify
      reference :page, on_delete: :nilify
    end
  end

  attachment do
    blob_resource Demo.Blob
    belongs_to_resource :post, Demo.Post
    belongs_to_resource :page, Demo.Page
  end

  attributes do
    uuid_primary_key :id
  end
end
