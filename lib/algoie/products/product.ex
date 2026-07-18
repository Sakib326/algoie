defmodule Algoie.Products.Product do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Algoie.Products.VariantGenerator

  postgres do
    table("products")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:slug, :string)
    attribute(:description, :string)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:brand_id, :uuid)
    attribute(:category_id, :uuid)

    attribute(:status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:draft, :active, :archived]],
      default: :draft
    )

    attribute(:product_type, :atom,
      allow_nil?: false,
      constraints: [one_of: [:simple, :variable]],
      default: :simple
    )

    attribute(:featured, :boolean, allow_nil?: false, default: false)
    attribute(:is_new, :boolean, allow_nil?: false, default: false)

    attribute(:attribute_definitions, :map, default: %{})

    attribute(:meta_title, :string)
    attribute(:meta_description, :string)

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  identities do
    identity(:unique_slug, [:store_id, :slug])
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    belongs_to :brand, Algoie.Products.Brand
    belongs_to :category, Algoie.Products.Category
    has_many :variants, Algoie.Products.Variant
    has_many :collection_products, Algoie.Products.CollectionProduct
    has_many :product_images, Algoie.Products.ProductImage
    has_many :product_tags, Algoie.Products.ProductTag
    has_many :product_categories, Algoie.Products.ProductCategory
    many_to_many :tags, Algoie.Products.Tag, through: Algoie.Products.ProductTag
    many_to_many :categories, Algoie.Products.Category, through: Algoie.Products.ProductCategory
  end

  actions do
    read :read do
      primary?(true)
      pagination offset?: true, default_limit: 12, countable: true
    end

    create :create do
      primary?(true)

      accept([
        :name,
        :slug,
        :description,
        :store_id,
        :brand_id,
        :category_id,
        :status,
        :product_type,
        :featured,
        :is_new,
        :attribute_definitions,
        :meta_title,
        :meta_description
      ])

      validate(&validate_seo_fields/2)
      validate(&validate_slug_format/2)
      validate(&validate_attribute_definitions/2)

      change(fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)
        slug = Ash.Changeset.get_attribute(changeset, :slug)

        if !slug && name do
          Ash.Changeset.change_attribute(changeset, :slug, Slug.slugify(name))
        else
          changeset
        end
      end)
    end

    update :update do
      primary?(true)
      require_atomic?(false)

      accept([
        :name,
        :slug,
        :description,
        :brand_id,
        :category_id,
        :status,
        :product_type,
        :featured,
        :is_new,
        :attribute_definitions,
        :meta_title,
        :meta_description
      ])

      validate(&validate_seo_fields/2)
      validate(&validate_slug_format/2)
      validate(&validate_attribute_definitions/2)

      change(fn changeset, _context ->
        name = Ash.Changeset.get_attribute(changeset, :name)
        slug = Ash.Changeset.get_attribute(changeset, :slug)

        if !slug && name do
          Ash.Changeset.change_attribute(changeset, :slug, Slug.slugify(name))
        else
          changeset
        end
      end)
    end

    destroy :destroy do
      primary?(true)
    end
  end

  @slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  defp validate_seo_fields(changeset, _context) do
    meta_title = Ash.Changeset.get_attribute(changeset, :meta_title)
    meta_desc = Ash.Changeset.get_attribute(changeset, :meta_description)

    cond do
      meta_title && byte_size(meta_title) > 60 ->
        {:error, "meta_title must be 60 characters or fewer for SEO"}

      meta_desc && byte_size(meta_desc) > 160 ->
        {:error, "meta_description must be 160 characters or fewer for SEO"}

      true ->
        :ok
    end
  end

  defp validate_slug_format(changeset, _context) do
    case Ash.Changeset.get_attribute(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        if Regex.match?(@slug_regex, slug) do
          :ok
        else
          {:error, "slug must be lowercase alphanumeric with hyphens (e.g. my-product-name)"}
        end

      _ ->
        :ok
    end
  end

  defp validate_attribute_definitions(changeset, _context) do
    product_type = Ash.Changeset.get_attribute(changeset, :product_type)
    attrs = Ash.Changeset.get_attribute(changeset, :attribute_definitions)

    cond do
      product_type == :simple && is_map(attrs) && map_size(attrs) > 0 ->
        {:error, "simple products cannot have attribute definitions"}

      product_type == :variable && (is_nil(attrs) || map_size(attrs) == 0) ->
        {:error, "variable products must define at least one attribute"}

      product_type == :variable && is_map(attrs) &&
          Enum.any?(attrs, fn {_k, values} -> !is_list(values) || values == [] end) ->
        {:error, "each attribute must have at least one value"}

      true ->
        :ok
    end
  end

  @doc """
  Generate the default variant for a simple product.
  Returns variant attrs map.
  """
  def default_variant_attrs(%{id: id, slug: slug}) do
    %{
      product_id: id,
      sku: slug || Ecto.UUID.generate(),
      price: Decimal.new(0),
      position: 0,
      option_values: %{},
      track_inventory?: true,
      stock: 0,
      low_stock_threshold: 10
    }
  end

  @doc """
  Generate variant attrs from attribute definitions for a variable product.
  """
  def generated_variant_attrs(%{id: id, slug: slug, attribute_definitions: attrs}) do
    attrs
    |> VariantGenerator.generate()
    |> Enum.with_index()
    |> Enum.map(fn {option_values, idx} ->
      %{
        product_id: id,
        sku: VariantGenerator.generate_sku(slug || Ecto.UUID.generate(), option_values),
        price: Decimal.new(0),
        position: idx,
        option_values: option_values,
        track_inventory?: true,
        stock: 0,
        low_stock_threshold: 10
      }
    end)
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
