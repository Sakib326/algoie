defmodule Algoie.Products.Brand do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("brands")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:slug, :string, allow_nil?: false)
    attribute(:description, :string)
    attribute(:image_url, :string)
    attribute(:meta_title, :string)
    attribute(:meta_description, :string)
    attribute(:store_id, :uuid, allow_nil?: false)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    has_many :products, Algoie.Products.Product
  end

  identities do
    identity(:unique_brand_slug, [:store_id, :slug])
  end

  actions do
    read :read do
      primary?(true)
      pagination(offset?: true, default_limit: 12, countable: true, required?: false)
    end

    create :create do
      primary?(true)
      accept([:name, :slug, :description, :image_url, :meta_title, :meta_description, :store_id])
      change(&set_slug/2)
      validate(&validate_seo/2)
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:name, :slug, :description, :image_url, :meta_title, :meta_description])
      change(&set_slug/2)
      validate(&validate_seo/2)
    end

    destroy :destroy do
      primary?(true)
    end
  end

  defp set_slug(changeset, _context) do
    name = Ash.Changeset.get_attribute(changeset, :name)
    slug = Ash.Changeset.get_attribute(changeset, :slug)

    if slug in [nil, ""] and is_binary(name),
      do: Ash.Changeset.change_attribute(changeset, :slug, Slug.slugify(name)),
      else: changeset
  end

  defp validate_seo(changeset, _context) do
    slug = Ash.Changeset.get_attribute(changeset, :slug)
    title = Ash.Changeset.get_attribute(changeset, :meta_title)
    description = Ash.Changeset.get_attribute(changeset, :meta_description)

    cond do
      slug && !Regex.match?(~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/, slug) ->
        {:error,
         field: :slug, message: "must contain lowercase letters, numbers, and hyphens only"}

      title && String.length(title) > 60 ->
        {:error, field: :meta_title, message: "must be 60 characters or fewer"}

      description && String.length(description) > 160 ->
        {:error, field: :meta_description, message: "must be 160 characters or fewer"}

      true ->
        :ok
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
