defmodule Algoie.Stores.StoreRegistry do
  use Ash.Resource,
    domain: Algoie.Stores,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("store_registry")
    repo(Algoie.Repo)
    schema("public")
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:slug, :string, allow_nil?: false)
    attribute(:tenant_id, :string, allow_nil?: false)
    attribute(:store_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
  end

  identities do
    identity(:unique_slug, [:slug])
  end

  actions do
    defaults([:read])

    create :create do
      accept([:slug, :tenant_id, :store_id])
    end

    destroy(:destroy)
  end
end
