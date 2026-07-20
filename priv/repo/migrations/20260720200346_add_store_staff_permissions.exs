defmodule Algoie.Repo.Migrations.AddStoreStaffPermissions do
  use Ecto.Migration

  def change do
    execute(
      """
      DO $$
      DECLARE tenant_schema record;
      BEGIN
        FOR tenant_schema IN
          SELECT schema_name
          FROM information_schema.schemata
          WHERE schema_name LIKE 'tenant\\_%' ESCAPE '\\'
        LOOP
          EXECUTE format(
            'ALTER TABLE %I.store_staff ADD COLUMN IF NOT EXISTS permissions text[]',
            tenant_schema.schema_name
          );
        END LOOP;
      END $$
      """,
      "SELECT 1"
    )
  end
end
