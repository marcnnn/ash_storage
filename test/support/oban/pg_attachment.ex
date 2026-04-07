defmodule AshStorage.Test.PgAttachment do
  @moduledoc false
  use Ash.Resource,
    domain: AshStorage.Test.PgDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage.AttachmentResource]

  postgres do
    table "storage_attachments"
    repo(AshStorage.TestRepo)

    references do
      reference :post, on_delete: :nilify
    end
  end

  attachment do
    blob_resource(AshStorage.Test.PgBlob)
    belongs_to_resource(:post, AshStorage.Test.PgPost)
  end

  attributes do
    uuid_primary_key :id
  end
end
