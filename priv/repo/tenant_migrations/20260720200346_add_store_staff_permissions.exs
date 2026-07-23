defmodule Algoie.Repo.TenantMigrations.AddStoreStaffPermissions do
  use Ecto.Migration

  def change do
    alter table(:store_staff, prefix: prefix()) do
      add_if_not_exists :permissions, {:array, :text}
    end
  end
end
