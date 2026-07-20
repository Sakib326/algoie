defmodule Algoie.Accounts.TenantPortal do
  @moduledoc "Tenant-level authorization and cross-store administration queries."

  alias Algoie.Accounts.{StorePermissions, StoreStaff, TenantMembership, User}
  alias Algoie.Repo
  require Ash.Query

  @manager_roles [:owner, :admin]

  def list_for_user(user_id) do
    Repo.query!(
      """
      SELECT t.id::text, t.slug, t.name, tm.role
      FROM public.tenant_memberships tm
      JOIN public.tenants t ON t.id = tm.tenant_id
      WHERE tm.user_id::text = $1
      ORDER BY t.name
      """,
      [to_string(user_id)]
    ).rows
    |> Enum.map(fn [id, slug, name, role] ->
      %{id: id, slug: slug, name: name, role: role_atom(role), tenant: "tenant_#{id}"}
    end)
  end

  def get_for_user(user_id, slug) do
    case Enum.find(list_for_user(user_id), &(&1.slug == slug)) do
      nil -> {:error, :forbidden}
      tenant -> {:ok, tenant}
    end
  end

  def load_stores(tenant, user_id) do
    access_by_id =
      if tenant.role in @manager_roles do
        :all
      else
        Algoie.Accounts.UserContext.load_all_user_stores(user_id)
        |> Enum.filter(&(&1.tenant == tenant.tenant))
        |> Map.new(&{&1.store_id, &1.permissions})
      end

    Repo.query!(
      """
      SELECT r.store_id::text, s.name, s.slug, s.status, s.currency, s.inserted_at
      FROM public.store_registry r
      JOIN "#{tenant.tenant}".stores s ON s.id = r.store_id
      WHERE r.tenant_id = $1
      ORDER BY s.inserted_at
      """,
      [tenant.id]
    ).rows
    |> Enum.map(fn [id, name, slug, status, currency, inserted_at] ->
      permissions =
        if access_by_id == :all,
          do: StorePermissions.keys(),
          else: Map.get(access_by_id, id, [])

      %{
        id: id,
        name: name,
        slug: slug,
        status: status,
        currency: currency,
        inserted_at: inserted_at,
        permissions: permissions
      }
    end)
    |> Enum.filter(&(access_by_id == :all or Map.has_key?(access_by_id, &1.id)))
  end

  def summary(tenant, stores) do
    store_ids =
      stores
      |> Enum.filter(&("reports.view" in &1.permissions))
      |> Enum.map(& &1.id)

    order_stats =
      if store_ids == [] do
        [0, Decimal.new(0), 0]
      else
        case Repo.query(
               """
               SELECT count(*)::bigint,
                      coalesce(sum(total_amount), 0),
                      count(DISTINCT customer_email)::bigint
               FROM "#{tenant.tenant}".orders
               WHERE store_id::text = ANY($1::text[])
               """,
               [store_ids]
             ) do
          {:ok, %{rows: [stats]}} -> stats
          _ -> [0, Decimal.new(0), 0]
        end
      end

    [orders, revenue, customers] = order_stats
    currencies = stores |> Enum.map(& &1.currency) |> Enum.uniq()

    revenue_label =
      case currencies do
        [currency] -> "#{currency} #{Decimal.to_string(revenue)}"
        [] -> Decimal.to_string(revenue)
        _ -> "Multiple currencies"
      end

    %{
      stores: length(stores),
      orders: orders,
      revenue: revenue,
      revenue_label: revenue_label,
      customers: customers
    }
  end

  def load_team(tenant) do
    members =
      Repo.query!(
        """
        SELECT tm.id::text, u.id::text, u.name, u.email::text, tm.role, tm.inserted_at
        FROM public.tenant_memberships tm
        JOIN public.users u ON u.id = tm.user_id
        WHERE tm.tenant_id::text = $1
        ORDER BY CASE tm.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END, u.email
        """,
        [tenant.id]
      ).rows
      |> Enum.map(fn [membership_id, user_id, name, email, role, inserted_at] ->
        %{
          membership_id: membership_id,
          user_id: user_id,
          name: name,
          email: email,
          role: role_atom(role),
          inserted_at: inserted_at,
          stores: []
        }
      end)

    assignments =
      Repo.query!("""
      SELECT ss.user_id::text, ss.store_id::text, s.name, ss.role, ss.permissions
      FROM "#{tenant.tenant}".store_staff ss
      JOIN "#{tenant.tenant}".stores s ON s.id = ss.store_id
      ORDER BY s.name
      """).rows
      |> Enum.group_by(
        &Enum.at(&1, 0),
        fn [_user_id, store_id, store_name, role, permissions] ->
          role = role_atom(role)

          %{
            store_id: store_id,
            store_name: store_name,
            role: role,
            permissions: StorePermissions.effective(role, permissions)
          }
        end
      )

    Enum.map(members, &Map.put(&1, :stores, Map.get(assignments, &1.user_id, [])))
  end

  def ensure_membership_from_store(membership) do
    tenant_id =
      membership.__metadata__.tenant
      |> to_string()
      |> String.replace_leading("tenant_", "")

    role = if membership.role == :owner, do: "admin", else: "member"

    Repo.query(
      """
      INSERT INTO public.tenant_memberships (tenant_id, user_id, role, inserted_at, updated_at)
      VALUES ($1::text::uuid, $2::text::uuid, $3, now(), now())
      ON CONFLICT (tenant_id, user_id) DO NOTHING
      """,
      [tenant_id, to_string(membership.user_id), role]
    )

    :ok
  end

  def add_member(manager, tenant, attrs) do
    with :ok <- authorize_manager(manager.id, tenant.id),
         {:ok, store_ids} <- validate_store_ids(tenant, attrs["store_ids"] || []),
         permissions <- StorePermissions.valid(attrs["permissions"] || []) do
      Repo.transaction(fn ->
        with {:ok, user, user_notifications} <- find_or_create_user(attrs),
             {:ok, _tenant_membership, tenant_notifications} <-
               ensure_tenant_membership(tenant.id, user.id),
             {:ok, store_notifications} <-
               assign_stores(tenant, user.id, store_ids, permissions) do
          {user, user_notifications ++ tenant_notifications ++ store_notifications}
        else
          {:error, error} -> Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, {user, notifications}} ->
          Ash.Notifier.notify(notifications)
          {:ok, user}

        error ->
          error
      end
    end
  end

  def remove_store_access(manager, tenant, user_id, store_id) do
    with :ok <- authorize_manager(manager.id, tenant.id),
         {:ok, membership} <-
           StoreStaff
           |> Ash.Query.filter(user_id == ^user_id and store_id == ^store_id)
           |> Ash.read_one(tenant: tenant.tenant, authorize?: false),
         false <- is_nil(membership),
         false <- membership.role == :owner do
      Ash.destroy(membership, actor: :system, tenant: tenant.tenant)
    else
      true -> {:error, "Owner store access cannot be removed here"}
      error -> error
    end
  end

  def change_member_role(manager, tenant, membership_id, role)
      when role in [:admin, :member] do
    with :ok <- authorize_manager(manager.id, tenant.id),
         {:ok, membership} <- Ash.get(TenantMembership, membership_id, authorize?: false),
         true <- to_string(membership.tenant_id) == tenant.id,
         false <- membership.role == :owner do
      Ash.update(membership, %{role: role}, actor: :system)
    else
      false -> {:error, "The tenant owner role cannot be changed"}
      _ -> {:error, :forbidden}
    end
  end

  def change_member_role(_, _, _, _), do: {:error, "Invalid tenant role"}

  def remove_member(manager, tenant, membership_id) do
    with :ok <- authorize_manager(manager.id, tenant.id),
         {:ok, membership} <- Ash.get(TenantMembership, membership_id, authorize?: false),
         true <- to_string(membership.tenant_id) == tenant.id,
         false <- membership.role == :owner,
         false <- store_owner?(tenant, membership.user_id),
         :ok <- remove_all_store_access(tenant, membership.user_id) do
      Ash.destroy(membership, actor: :system)
    else
      false -> {:error, "Store owners must transfer ownership before leaving the tenant"}
      _ -> {:error, :forbidden}
    end
  end

  defp authorize_manager(user_id, tenant_id) do
    case Repo.query(
           "SELECT role FROM public.tenant_memberships WHERE tenant_id::text = $1 AND user_id::text = $2 LIMIT 1",
           [tenant_id, to_string(user_id)]
         ) do
      {:ok, %{rows: [[role]]}} when role in ["owner", "admin"] -> :ok
      _ -> {:error, :forbidden}
    end
  end

  defp validate_store_ids(tenant, store_ids) do
    requested = MapSet.new(store_ids)

    actual =
      Repo.query!("SELECT store_id::text FROM public.store_registry WHERE tenant_id = $1", [
        tenant.id
      ]).rows
      |> MapSet.new(&List.first/1)

    if MapSet.subset?(requested, actual),
      do: {:ok, MapSet.to_list(requested)},
      else: {:error, :forbidden}
  end

  defp find_or_create_user(attrs) do
    email = attrs |> Map.get("email", "") |> String.trim()

    case User
         |> Ash.Query.filter(email == ^email)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        Ash.create(
          User,
          %{
            name: String.trim(attrs["name"] || ""),
            email: email,
            password: attrs["password"] || ""
          },
          action: :register_with_password,
          actor: :system,
          return_notifications?: true
        )

      {:ok, user} ->
        {:ok, user, []}

      error ->
        error
    end
  end

  defp ensure_tenant_membership(tenant_id, user_id) do
    case TenantMembership
         |> Ash.Query.filter(tenant_id == ^tenant_id and user_id == ^user_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        Ash.create(TenantMembership, %{tenant_id: tenant_id, user_id: user_id, role: :member},
          actor: :system,
          return_notifications?: true
        )

      {:ok, membership} ->
        {:ok, membership, []}

      error ->
        error
    end
  end

  defp assign_stores(tenant, user_id, store_ids, permissions) do
    Enum.reduce_while(store_ids, {:ok, []}, fn store_id, {:ok, notifications} ->
      result =
        case StoreStaff
             |> Ash.Query.filter(user_id == ^user_id and store_id == ^store_id)
             |> Ash.read_one(tenant: tenant.tenant, authorize?: false) do
          {:ok, nil} ->
            Ash.create(
              StoreStaff,
              %{user_id: user_id, store_id: store_id, role: :staff, permissions: permissions},
              actor: :system,
              tenant: tenant.tenant,
              return_notifications?: true
            )

          {:ok, %{role: :owner}} ->
            {:ok, :owner_unchanged, []}

          {:ok, membership} ->
            Ash.update(membership, %{permissions: permissions},
              actor: :system,
              tenant: tenant.tenant,
              return_notifications?: true
            )

          error ->
            error
        end

      case result do
        {:ok, _, action_notifications} ->
          {:cont, {:ok, notifications ++ action_notifications}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp store_owner?(tenant, user_id) do
    case Repo.query(
           "SELECT 1 FROM \"#{tenant.tenant}\".store_staff WHERE user_id::text = $1 AND role = 'owner' LIMIT 1",
           [to_string(user_id)]
         ) do
      {:ok, %{rows: [[1]]}} -> true
      _ -> false
    end
  end

  defp remove_all_store_access(tenant, user_id) do
    Repo.query!(
      "DELETE FROM \"#{tenant.tenant}\".store_staff WHERE user_id::text = $1 AND role != 'owner'",
      [to_string(user_id)]
    )

    :ok
  end

  defp role_atom("owner"), do: :owner
  defp role_atom("admin"), do: :admin
  defp role_atom("member"), do: :member
  defp role_atom("staff"), do: :staff
end
