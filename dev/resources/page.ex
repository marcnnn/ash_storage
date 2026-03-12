defmodule Demo.Page do
  @moduledoc false
  use Ash.Resource,
    domain: Demo.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStorage]

  postgres do
    table "pages"
    repo(Demo.Repo)
  end

  storage do
    service(
      {AshStorage.Service.Disk,
       root: "tmp/dev_storage",
       base_url: "/disk_files",
       secret: "dev-secret-key-for-signed-urls!!"}
    )

    blob_resource(Demo.Blob)
    attachment_resource(Demo.Attachment)

    has_one_attached :cover_image,
      analyzers: [
        Demo.Analyzers.FileInfo,
        {Demo.Analyzers.ImageDimensions, analyze: :oban}
      ]

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
