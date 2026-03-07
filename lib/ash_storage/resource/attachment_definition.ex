defmodule AshStorage.Resource.AttachmentDefinition do
  @moduledoc "Represents a configured attachment on a resource"
  defstruct [
    :name,
    :type,
    :service,
    :dependent,
    :__spark_metadata__
  ]

  @shared_schema [
    name: [
      type: :atom,
      doc: "The name of the attachment (e.g. `:avatar`, `:documents`).",
      required: true
    ],
    service: [
      type: {:tuple, [:module, :keyword_list]},
      doc:
        "The storage service to use for this attachment, as a `{module, opts}` tuple. Configurable via application config.",
      required: false
    ],
    dependent: [
      type: {:one_of, [:purge, :detach, false]},
      doc:
        "What to do with the attachment when the parent record is destroyed. `:purge` deletes the blob and file, `:detach` removes the association, `false` does nothing.",
      default: :purge
    ]
  ]

  def has_one_schema, do: @shared_schema
  def has_many_schema, do: @shared_schema
end
