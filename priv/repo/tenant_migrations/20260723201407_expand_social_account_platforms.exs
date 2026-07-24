defmodule Algoie.Repo.TenantMigrations.ExpandSocialAccountPlatforms do
  use Ecto.Migration

  @constraint :social_accounts_platform_check

  def up do
    drop constraint(:social_accounts, @constraint, prefix: prefix())

    create constraint(:social_accounts, @constraint,
             check: "platform IN ('facebook','instagram','whatsapp','tiktok','metaads')",
             prefix: prefix()
           )
  end

  def down do
    drop constraint(:social_accounts, @constraint, prefix: prefix())

    create constraint(:social_accounts, @constraint,
             check: "platform IN ('facebook','instagram','whatsapp','tiktok')",
             prefix: prefix()
           )
  end
end
