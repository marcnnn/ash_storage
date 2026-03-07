defmodule AshStorage.Resource.Transformers.SetupStorage do
  @moduledoc false
  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    attachments = Spark.Dsl.Extension.get_entities(dsl_state, [:storage])

    has_dependent? =
      Enum.any?(attachments, fn att ->
        att.dependent in [:purge, :detach]
      end)

    if has_dependent? do
      Ash.Resource.Builder.add_change(
        dsl_state,
        AshStorage.Resource.Changes.HandleDependentAttachments,
        on: :destroy
      )
    else
      {:ok, dsl_state}
    end
  end
end
