defmodule Algoie.Repo.TenantMigrations.DropStoreStaffUserFk do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE \"#{prefix()}\".store_staff DROP CONSTRAINT IF EXISTS store_staff_user_id_fkey"
  end

  def down do
    execute "ALTER TABLE \"#{prefix()}\".store_staff ADD CONSTRAINT store_staff_user_id_fkey FOREIGN KEY (user_id) REFERENCES \"#{prefix()}\".users(id)"
  end
end
