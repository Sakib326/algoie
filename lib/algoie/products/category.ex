defmodule Algoie.Products.Category do
  use Ash.Resource,
    domain: Algoie.Products,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("categories")
    repo(Algoie.Repo)
  end

  multitenancy do
    strategy(:context)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false)
    attribute(:store_id, :uuid, allow_nil?: false)
    attribute(:parent_id, :uuid)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :store, Algoie.Stores.Store, allow_nil?: false
    belongs_to :parent, Algoie.Products.Category
    has_many :children, Algoie.Products.Category, destination_attribute: :parent_id
    has_many :products, Algoie.Products.Product
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)
      accept([:name, :store_id, :parent_id])
    end

    update :update do
      primary?(true)
      require_atomic?(false)
      accept([:name, :parent_id])

      change(fn changeset, _context ->
        parent_id = Ash.Changeset.get_attribute(changeset, :parent_id)
        category_id = Ash.Changeset.get_data(changeset, :id)

        if parent_id && category_id do
          # For existing records, tenant is in __meta__.tenant
          # For new records (create), check the changeset for tenant
          tenant =
            changeset.data
            |> Map.get(:__meta__, %{})
            |> Map.get(:schema, nil)
            |> then(fn
              nil ->
                # During create, try to get tenant from context
                changeset.context[:tenant] || changeset.context[:domain_tenant]

              _ ->
                changeset.data.__metadata__.tenant
            end)

          case walk_parent_chain(parent_id, category_id, tenant) do
            :ok -> changeset
            :cycle -> Ash.Changeset.add_error(changeset, :parent_id, "creates a cycle")
          end
        else
          changeset
        end
      end)
    end

    destroy(:destroy)
  end

  defp walk_parent_chain(parent_id, target_id, tenant) do
    if parent_id == target_id do
      :cycle
    else
      case Ash.get(__MODULE__, parent_id, tenant: tenant, authorize?: false) do
        {:ok, %{parent_id: nil}} -> :ok
        {:ok, %{parent_id: next}} -> walk_parent_chain(next, target_id, tenant)
        _ -> :ok
      end
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if(Algoie.Policies.Checks.ActorIsSystem)
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
