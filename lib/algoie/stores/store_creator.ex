defmodule Algoie.Stores.StoreCreator do
  @moduledoc "Creates an additional store inside a tenant already owned by a global user."

  alias Algoie.Accounts.{StoreStaff, UserContext}
  alias Algoie.Repo
  alias Algoie.Stores.Store

  @tenant_pattern ~r/^tenant_[0-9a-f-]{36}$/

  def create_for_owner(user, tenant, attrs) do
    name = attrs |> Map.get("name", "") |> String.trim()
    slug = attrs |> Map.get("slug", "") |> normalize_slug()

    with :ok <- authorize_owner(user, tenant),
         :ok <- validate_name(name),
         :ok <- validate_slug(slug),
         :ok <- ensure_tenant_active(tenant) do
      Repo.transaction(fn ->
        with {:ok, store, store_notifications} <-
               Ash.create(Store, %{name: name, slug: slug},
                 actor: :system,
                 tenant: tenant,
                 return_notifications?: true
               ),
             {:ok, membership_notifications} <-
               create_manager_memberships(store, user.id, tenant) do
          {store, store_notifications ++ membership_notifications}
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, {store, notifications}} ->
          Ash.Notifier.notify(notifications)
          {:ok, store}

        error ->
          error
      end
    end
  end

  def normalize_slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp create_manager_memberships(store, creator_id, "tenant_" <> tenant_id = tenant) do
    managers =
      Repo.query!(
        "SELECT user_id::text, role FROM public.tenant_memberships WHERE tenant_id::text = $1 AND role IN ('owner', 'admin')",
        [tenant_id]
      ).rows
      |> Enum.map(fn [user_id, role] -> {user_id, role} end)
      |> then(fn rows ->
        if Enum.any?(rows, &(elem(&1, 0) == to_string(creator_id))),
          do: rows,
          else: [{to_string(creator_id), "owner"} | rows]
      end)

    Enum.reduce_while(managers, {:ok, []}, fn {user_id, tenant_role}, {:ok, notifications} ->
      attrs =
        if tenant_role == "owner" do
          %{user_id: user_id, store_id: store.id, role: :owner}
        else
          %{
            user_id: user_id,
            store_id: store.id,
            role: :staff,
            permissions: Algoie.Accounts.StorePermissions.keys()
          }
        end

      case Ash.create(StoreStaff, attrs,
             actor: :system,
             tenant: tenant,
             return_notifications?: true
           ) do
        {:ok, _membership, action_notifications} ->
          {:cont, {:ok, notifications ++ action_notifications}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp authorize_owner(%{id: user_id}, tenant) when is_binary(tenant) do
    tenant_id = String.replace_leading(tenant, "tenant_", "")

    tenant_manager? =
      case Repo.query(
             "SELECT 1 FROM public.tenant_memberships WHERE tenant_id::text = $1 AND user_id::text = $2 AND role IN ('owner', 'admin') LIMIT 1",
             [tenant_id, to_string(user_id)]
           ) do
        {:ok, %{rows: [[1]]}} -> true
        _ -> false
      end

    legacy_store_owner? =
      Enum.any?(
        UserContext.load_all_user_stores(user_id),
        &(&1.tenant == tenant and &1.role == :owner)
      )

    if Regex.match?(@tenant_pattern, tenant) and (tenant_manager? or legacy_store_owner?) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_owner(_, _), do: {:error, :forbidden}

  defp validate_name(name) when byte_size(name) in 2..100, do: :ok
  defp validate_name(_), do: {:error, "Store name must be between 2 and 100 characters"}

  defp validate_slug(slug) when byte_size(slug) in 3..63, do: :ok
  defp validate_slug(_), do: {:error, "Store slug must be between 3 and 63 characters"}

  defp ensure_tenant_active("tenant_" <> tenant_id) do
    case Repo.query(
           "SELECT 1 FROM public.tenants WHERE id::text = $1 AND billing_status != 'suspended' LIMIT 1",
           [tenant_id]
         ) do
      {:ok, %{rows: [[1]]}} -> :ok
      _ -> {:error, "This tenant is suspended and cannot create stores"}
    end
  end
end
