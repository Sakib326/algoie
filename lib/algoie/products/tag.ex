defmodule Algoie.Products.Tag do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("tags")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:slug, :string, allow_nil?: false)
    attribute(:store_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:store_id, :slug])
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :product_tags, Algoie.Products.ProductTag
    many_to_many :products, Algoie.Products.Product, through: Algoie.Products.ProductTag
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :slug, :store_id])

      validate(fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)
        slug = Ash.Changeset.get_attribute(changeset, :slug)

        cond do
          is_nil(name) || byte_size(name) == 0 ->
            {:error, "name is required"}

          byte_size(name) > 100 ->
            {:error, "name must be 100 characters or fewer"}

          !Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug || "") ->
            {:error, "slug must be a valid slug (lowercase alphanumeric with hyphens)"}

          true ->
            :ok
        end
      end)
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:name, :slug])

      validate(fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)
        slug = Ash.Changeset.get_attribute(changeset, :slug)

        cond do
          name && byte_size(name) > 100 ->
            {:error, "name must be 100 characters or fewer"}

          slug && !Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug) ->
            {:error, "slug must be a valid slug (lowercase alphanumeric with hyphens)"}

          true ->
            :ok
        end
      end)
    end

    destroy :destroy do
      primary?(true)
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end

    policy action_type([:read, :update]) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :staff})
    end

    policy action_type(:destroy) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
      authorize_if({Algoie.Policies.Checks.ActorHasStoreAccess, level: :owner})
    end
  end
end
