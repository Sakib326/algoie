defmodule Algoie.Repo.TenantMigrations.CreateSocialPublishing do
  use Ecto.Migration

  @platforms ~w(facebook instagram whatsapp tiktok)

  def up do
    create_if_not_exists table(:social_profiles, primary_key: false, prefix: prefix()) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :store_id, references(:stores, type: :uuid, prefix: prefix(), on_delete: :delete_all),
        null: false

      add :provider_profile_id, :text, null: false
      add :name, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:social_profiles, [:store_id], prefix: prefix())

    create_if_not_exists unique_index(:social_profiles, [:provider_profile_id],
                           prefix: prefix()
                         )

    create_if_not_exists table(:social_accounts, primary_key: false, prefix: prefix()) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :social_profile_id,
          references(:social_profiles, type: :uuid, prefix: prefix(), on_delete: :delete_all),
          null: false

      add :provider_account_id, :text, null: false
      add :platform, :text, null: false
      add :status, :text, null: false, default: "connected"
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:social_accounts, [:provider_account_id],
                           prefix: prefix()
                         )

    create_if_not_exists index(:social_accounts, [:social_profile_id], prefix: prefix())

    create constraint(:social_accounts, :social_accounts_platform_check,
             check: "platform IN (#{Enum.map_join(@platforms, ",", &"'#{&1}'")})",
             prefix: prefix()
           )

    create constraint(:social_accounts, :social_accounts_status_check,
             check: "status IN ('connected','disconnected','needs_reauth')",
             prefix: prefix()
           )
  end

  def down do
    drop table(:social_accounts, prefix: prefix())
    drop table(:social_profiles, prefix: prefix())
  end
end
