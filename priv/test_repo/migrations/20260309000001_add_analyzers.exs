defmodule AshStorage.TestRepo.Migrations.AddAnalyzers do
  use Ecto.Migration

  def up do
    alter table(:storage_blobs) do
      add :analyzers, :map, default: %{}
    end
  end

  def down do
    alter table(:storage_blobs) do
      remove :analyzers
    end
  end
end
