defmodule Algoie.Repo.Migrations.AddTenantPortal do
  use Ecto.Migration

  def up do
    alter table(:tenants, prefix: "public") do
      add :slug, :text
    end

    execute("""
    UPDATE public.tenants
    SET slug = trim(both '-' from lower(regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g')))
               || '-' || substr(id::text, 1, 8)
    WHERE slug IS NULL
    """)

    alter table(:tenants, prefix: "public") do
      modify :slug, :text, null: false
    end

    create unique_index(:tenants, [:slug], prefix: "public", name: "tenants_unique_slug_index")

    create table(:tenant_memberships, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true, null: false, default: fragment("gen_random_uuid()")
      add :role, :text, null: false, default: "member"

      add :tenant_id,
          references(:tenants, type: :uuid, prefix: "public", on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :uuid, prefix: "public", on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenant_memberships, [:tenant_id, :user_id],
             prefix: "public",
             name: "tenant_memberships_unique_tenant_user_index"
           )

    execute("""
    INSERT INTO public.tenant_memberships (tenant_id, user_id, role, inserted_at, updated_at)
    SELECT t.id, u.id, 'owner', now(), now()
    FROM public.tenants t
    JOIN public.users u ON lower(u.email::text) = lower(t.owner_email::text)
    ON CONFLICT (tenant_id, user_id) DO UPDATE SET role = 'owner', updated_at = now()
    """)

    execute("""
    DO $$
    DECLARE tenant_row record;
    BEGIN
      FOR tenant_row IN SELECT id FROM public.tenants LOOP
        IF to_regclass(format('%I.store_staff', 'tenant_' || tenant_row.id::text)) IS NOT NULL THEN
          EXECUTE format(
            'INSERT INTO public.tenant_memberships (tenant_id, user_id, role, inserted_at, updated_at)
             SELECT $1, user_id, CASE WHEN bool_or(role = ''owner'') THEN ''admin'' ELSE ''member'' END, now(), now()
             FROM %I.store_staff GROUP BY user_id
             ON CONFLICT (tenant_id, user_id) DO NOTHING',
            'tenant_' || tenant_row.id::text
          ) USING tenant_row.id;
        END IF;
      END LOOP;
    END $$
    """)
  end

  def down do
    drop table(:tenant_memberships, prefix: "public")
    drop unique_index(:tenants, [:slug], prefix: "public", name: "tenants_unique_slug_index")

    alter table(:tenants, prefix: "public") do
      remove :slug
    end
  end
end
