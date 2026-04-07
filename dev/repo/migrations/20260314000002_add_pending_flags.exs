defmodule Demo.Repo.Migrations.AddPendingFlags do
  use Ecto.Migration

  def up do
    alter table(:storage_blobs) do
      add :pending_analyzers, :boolean, null: false, default: false
      add :pending_variants, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:storage_blobs) do
      remove :pending_analyzers
      remove :pending_variants
    end
  end
end
