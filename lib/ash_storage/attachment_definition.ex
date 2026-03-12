defmodule AshStorage.AttachmentDefinition do
  @moduledoc "Represents a configured attachment on a resource"
  defstruct [
    :name,
    :type,
    :service,
    :dependent,
    :analyzers,
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
    ],
    analyzers: [
      type:
        {:list,
         {:or,
          [
            :atom,
            {:tuple, [:atom, :keyword_list]}
          ]}},
      doc: """
      A list of analyzer modules (implementing `AshStorage.Analyzer`) to run on uploaded files.

      Each entry can be a module or a `{module, opts}` tuple. Opts can include:
      - `:analyze` - `:eager` (default) to run synchronously during attach, or `:oban` for background processing via AshOban
      - Any other opts are passed to the analyzer's `analyze/2` callback

      Analyzer state is tracked on the blob's `analyzers` attribute as a map keyed by module name,
      with `"status"` (`"pending"` or `"complete"`) and `"opts"`.

      When using `analyze: :oban`, you must configure an AshOban trigger on your blob resource
      that calls the `:run_pending_analyzers` action.

      ## Examples

          analyzers: [MyApp.ImageAnalyzer]
          analyzers: [{MyApp.VideoAnalyzer, analyze: :oban, format: :mp4}]
      """,
      default: []
    ]
  ]

  @doc false
  def normalize_analyzers(analyzers) do
    Enum.map(analyzers, fn
      {module, opts} when is_atom(module) and is_list(opts) ->
        {analyze, opts} = Keyword.pop(opts, :analyze, :eager)
        {module, analyze, opts}

      module when is_atom(module) ->
        {module, :eager, []}
    end)
  end

  def has_one_schema, do: @shared_schema
  def has_many_schema, do: @shared_schema
end
