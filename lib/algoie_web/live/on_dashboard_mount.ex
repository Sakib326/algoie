defmodule AlgoieWeb.Live.OnDashboardMount do
  @moduledoc """
  OnMount hook for dashboard routes.
  Loads current_user from session, resolves store context, and redirects to sign-in if not authenticated.

  Supports multi-store users via session-stored store list and active store selection.
  """

  import Phoenix.LiveView, only: [redirect: 2]
  import Phoenix.Component, only: [assign: 3, assign_new: 3]
  import Ecto.Query

  def on_mount(:default, _params, session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, redirect(socket, to: "/sign-in")}

      user ->
        socket =
          socket
          |> assign_new(:user_stores, fn -> session["user_stores"] || [] end)
          |> assign_new(:tenant, fn -> session["store_tenant"] end)
          |> assign_new(:store_id, fn -> session["store_id"] end)
          |> assign_new(:store_name, fn -> session["store_name"] || "Store" end)
          |> assign_new(:current_scope, fn -> %{user: user} end)

        if socket.assigns.tenant do
          {:cont, socket}
        else
          # No store context — try to load from user's memberships
          case load_default_store(user) do
            {:ok, %{tenant: tenant, store_id: store_id, store_name: store_name, stores: stores}} ->
              socket =
                socket
                |> assign(:tenant, tenant)
                |> assign(:store_id, store_id)
                |> assign(:store_name, store_name)
                |> assign(:user_stores, stores)

              {:cont, socket}

            _ ->
              {:halt, redirect(socket, to: "/register")}
          end
        end
    end
  end

  defp load_default_store(user) do
    user_id = user.id

    case get_tenants_with_stores(user_id) do
      [] ->
        {:error, :no_store}

      [{tenant, store_id, store_name, role} | rest] ->
        all_stores =
          [{tenant, store_id, store_name, role} | rest]
          |> Enum.map(fn {t, sid, sname, r} ->
            %{store_id: sid, store_name: sname, tenant: t, role: r}
          end)

        {:ok,
         %{
           tenant: tenant,
           store_id: store_id,
           store_name: store_name,
           stores: all_stores
         }}
    end
  end

  defp get_tenants_with_stores(user_id) do
    case Algoie.Repo.all(from(t in "tenants", prefix: "public", select: fragment("?::text", t.id))) do
      [] ->
        []

      tenant_ids ->
        Enum.flat_map(tenant_ids, fn tenant_id ->
          schema = "tenant_#{tenant_id}"

          case Ecto.Adapters.SQL.query(
                 Algoie.Repo,
                 """
                 SELECT ss.store_id::text, s.name, ss.role
                 FROM "#{schema}".store_staff ss
                 JOIN "#{schema}".stores s ON s.id = ss.store_id
                 WHERE ss.user_id::text = $1
                 """,
                 [user_id]
               ) do
            {:ok, %{rows: rows}} ->
              Enum.map(rows, fn [store_id, store_name, role] ->
                {schema, store_id, store_name, role}
              end)

            _ ->
              []
          end
        end)
    end
  end
end
