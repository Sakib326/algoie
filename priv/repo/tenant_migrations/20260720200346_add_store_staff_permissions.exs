defmodule Algoie.Repo.TenantMigrations.AddStoreStaffPermissions do
  use Ecto.Migration

  def change do
    alter table(:store_staff, prefix: prefix()) do
      add :permissions, {:array, :text}
    end
  end
end
