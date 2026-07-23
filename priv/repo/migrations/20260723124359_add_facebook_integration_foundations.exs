defmodule Algoie.Repo.Migrations.AddFacebookIntegrationFoundations do
  use Ecto.Migration

  def change do
    alter table(:social_publishing_settings) do
      add :webhook_id, :text
      add :webhook_secret_ciphertext, :text
    end

    create table(:social_account_registry, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :provider_account_id, :text, null: false
      add :tenant, :text, null: false
      add :store_id, :uuid, null: false
      add :local_account_id, :uuid, null: false
      add :platform, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:social_account_registry, [:provider_account_id])
    create index(:social_account_registry, [:tenant, :store_id])

    create table(:zernio_webhook_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :event_id, :text, null: false
      add :event, :text, null: false
      add :provider_account_id, :text
      add :processed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:zernio_webhook_receipts, [:event_id])
    create index(:zernio_webhook_receipts, [:provider_account_id, :inserted_at])

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
          IF to_regclass(format('%I.social_accounts', tenant_schema.schema_name)) IS NOT NULL THEN
            EXECUTE format(
              'INSERT INTO public.social_account_registry
                 (id, provider_account_id, tenant, store_id, local_account_id, platform, inserted_at, updated_at)
               SELECT gen_random_uuid(), a.provider_account_id, %L, p.store_id, a.id, a.platform, now(), now()
               FROM %I.social_accounts a
               JOIN %I.social_profiles p ON p.id = a.social_profile_id
               ON CONFLICT (provider_account_id) DO UPDATE SET
                 tenant = EXCLUDED.tenant,
                 store_id = EXCLUDED.store_id,
                 local_account_id = EXCLUDED.local_account_id,
                 platform = EXCLUDED.platform,
                 updated_at = now()',
              tenant_schema.schema_name,
              tenant_schema.schema_name,
              tenant_schema.schema_name
            );
          END IF;
        END LOOP;
      END $$;
      """,
      "SELECT 1"
    )
  end
end
