defmodule AshStorage.BlobResource.Changes.CompleteAnalysis do
  @moduledoc """
  A change that atomically updates a blob's analyzer status and merges metadata.

  Used by the `:complete_analysis` action. On SQL data layers, this uses
  `jsonb_set` and `||` fragments for true atomic updates, preventing race
  conditions when multiple async analyzer jobs complete concurrently.

  On non-SQL data layers (e.g. ETS), falls back to in-memory map manipulation.
  """
  use Ash.Resource.Change

  require Ash.Expr

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      analyzer_key = Ash.Changeset.get_argument(changeset, :analyzer_key)
      status = Ash.Changeset.get_argument(changeset, :status)
      metadata_to_merge = Ash.Changeset.get_argument(changeset, :metadata_to_merge) || %{}

      record = changeset.data
      current_analyzers = record.analyzers || %{}
      current_metadata = record.metadata || %{}

      updated_analyzers = put_in(current_analyzers, [analyzer_key, "status"], status)
      updated_metadata = Map.merge(current_metadata, metadata_to_merge)

      changeset
      |> Ash.Changeset.force_change_attribute(:analyzers, updated_analyzers)
      |> Ash.Changeset.force_change_attribute(:metadata, updated_metadata)
    end)
  end

  @impl true
  def atomic(changeset, _opts, _context) do
    if Ash.DataLayer.data_layer(changeset.resource) == AshPostgres.DataLayer do
      do_atomic(changeset)
    else
      do_non_atomic(changeset)
    end
  end

  defp do_non_atomic(changeset) do
    analyzer_key = Ash.Changeset.get_argument(changeset, :analyzer_key)
    status = Ash.Changeset.get_argument(changeset, :status)
    metadata_to_merge = Ash.Changeset.get_argument(changeset, :metadata_to_merge) || %{}

    record = changeset.data
    current_analyzers = record.analyzers || %{}
    current_metadata = record.metadata || %{}

    updated_analyzers = put_in(current_analyzers, [analyzer_key, "status"], status)
    updated_metadata = Map.merge(current_metadata, metadata_to_merge)

    {:atomic,
     %{
       analyzers: {:atomic, updated_analyzers},
       metadata: {:atomic, updated_metadata}
     }}
  end

  defp do_atomic(changeset) do
    analyzer_key = Ash.Changeset.get_argument(changeset, :analyzer_key)
    status = Ash.Changeset.get_argument(changeset, :status)
    metadata_to_merge = Ash.Changeset.get_argument(changeset, :metadata_to_merge) || %{}

    atomics =
      %{
        analyzers:
          {:atomic,
           Ash.Expr.expr(
             fragment(
               "jsonb_set(coalesce(?, '{}'), ?::text[], to_jsonb(?::text))",
               analyzers,
               ^[analyzer_key, "status"],
               ^status
             )
           )}
      }

    atomics =
      if metadata_to_merge != %{} do
        Map.put(
          atomics,
          :metadata,
          {:atomic,
           Ash.Expr.expr(
             fragment(
               "coalesce(?, '{}') || ?",
               metadata,
               ^metadata_to_merge
             )
           )}
        )
      else
        atomics
      end

    {:atomic, atomics}
  end
end
