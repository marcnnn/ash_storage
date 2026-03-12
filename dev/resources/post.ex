defmodule Demo.Post do
  @moduledoc false
  use Ash.Resource,
    domain: Demo.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage]

  postgres do
    table "posts"
    repo(Demo.Repo)
  end

  storage do
    service(
      {AshStorage.Service.S3,
       bucket: "ash-storage-dev",
       region: "us-east-1",
       access_key_id: "minioadmin",
       secret_access_key: "minioadmin",
       endpoint_url: "http://localhost:19000",
       presigned: true}
    )

    blob_resource(Demo.Blob)
    attachment_resource(Demo.Attachment)

    has_one_attached :cover_image,
      analyzers: [Demo.Analyzers.FileInfo, Demo.Analyzers.ImageDimensions]

    has_many_attached :documents,
      analyzers: [Demo.Analyzers.FileInfo]
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:title], update: [:title]]
  end
end
