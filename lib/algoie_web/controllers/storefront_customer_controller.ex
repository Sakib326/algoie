defmodule AlgoieWeb.StorefrontCustomerController do
  use AlgoieWeb, :controller

  require Ash.Query

  alias Algoie.Customers.CustomerAddress
  alias Algoie.Orders.{Order, OrderLineItem}
  alias Algoie.Storefront.CustomerAccounts

  def register(conn, _params) do
    if conn.assigns.current_customer,
      do: redirect(conn, to: ~p"/account"),
      else: render_page(conn, :register, %{form: form(%{}, :registration)})
  end

  def create_account(conn, %{"registration" => params}) do
    context = context(conn)

    case CustomerAccounts.register(context.tenant, context.store_id, params) do
      {:ok, customer} ->
        conn
        |> put_session("storefront_customer_id", to_string(customer.id))
        |> put_flash(:info, "Your customer account is ready")
        |> redirect(to: ~p"/account")

      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, error_text(error))
        |> render_page(:register, %{form: form(params, :registration)})
    end
  end

  def sign_in(conn, _params) do
    if conn.assigns.current_customer,
      do: redirect(conn, to: ~p"/account"),
      else: render_page(conn, :sign_in, %{form: form(%{}, :login)})
  end

  def authenticate(conn, %{"login" => params}) do
    context = context(conn)

    case CustomerAccounts.authenticate(
           context.tenant,
           context.store_id,
           params["email"],
           params["password"]
         ) do
      {:ok, customer} ->
        conn
        |> configure_session(renew: true)
        |> put_session("storefront_customer_id", to_string(customer.id))
        |> put_flash(:info, "Welcome back, #{customer.name}")
        |> redirect(to: ~p"/account")

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, "Email or password is incorrect")
        |> render_page(:sign_in, %{form: form(%{"email" => params["email"]}, :login)})
    end
  end

  def sign_out(conn, _params) do
    conn
    |> delete_session("storefront_customer_id")
    |> put_flash(:info, "You have signed out")
    |> redirect(to: ~p"/")
  end

  def show(conn, _params) do
    with {:ok, customer} <- require_customer(conn) do
      context = context(conn)
      render_account(conn, context, customer)
    else
      {:error, conn} -> conn
    end
  end

  def update_profile(conn, %{"profile" => params}) do
    with {:ok, customer} <- require_customer(conn) do
      case Ash.update(customer, params,
             action: :update_account,
             tenant: context(conn).tenant,
             authorize?: false
           ) do
        {:ok, _customer} ->
          conn |> put_flash(:info, "Profile updated") |> redirect(to: ~p"/account")

        {:error, error} ->
          conn |> put_flash(:error, error_text(error)) |> redirect(to: ~p"/account")
      end
    else
      {:error, conn} -> conn
    end
  end

  def create_address(conn, %{"address" => params}) do
    with {:ok, customer} <- require_customer(conn) do
      context = context(conn)

      attrs =
        params
        |> Map.put("customer_id", customer.id)
        |> Map.put("store_id", context.store_id)

      case Ash.create(CustomerAddress, attrs, tenant: context.tenant, authorize?: false) do
        {:ok, _address} ->
          conn |> put_flash(:info, "Address added") |> redirect(to: ~p"/account")

        {:error, error} ->
          conn |> put_flash(:error, error_text(error)) |> redirect(to: ~p"/account")
      end
    else
      {:error, conn} -> conn
    end
  end

  def order(conn, %{"id" => id}) do
    with {:ok, customer} <- require_customer(conn) do
      context = context(conn)

      result =
        Order
        |> Ash.Query.filter(
          id == ^id and customer_id == ^customer.id and store_id == ^context.store_id
        )
        |> Ash.read_one(tenant: context.tenant, authorize?: false)

      case result do
        {:ok, order} ->
          items =
            OrderLineItem
            |> Ash.Query.filter(order_id == ^order.id)
            |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)

          render_page(conn, :order, %{customer: customer, order: order, items: items})

        _ ->
          conn |> put_status(:not_found) |> put_view(AlgoieWeb.ErrorHTML) |> render(:"404")
      end
    else
      {:error, conn} -> conn
    end
  end

  defp render_account(conn, context, customer) do
    addresses =
      CustomerAddress
      |> Ash.Query.filter(customer_id == ^customer.id and store_id == ^context.store_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)

    orders =
      Order
      |> Ash.Query.filter(customer_id == ^customer.id and store_id == ^context.store_id)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!(tenant: context.tenant, authorize?: false, page: false)

    render_page(conn, :account, %{
      customer: customer,
      addresses: addresses,
      orders: orders,
      profile_form: form(%{"name" => customer.name, "phone" => customer.phone}, :profile),
      address_form: form(%{"country" => "Bangladesh", "label" => "Home"}, :address)
    })
  end

  defp require_customer(conn) do
    case conn.assigns.current_customer do
      nil ->
        {:error,
         conn
         |> put_flash(:error, "Sign in to view your account")
         |> redirect(to: ~p"/account/sign-in")}

      customer ->
        {:ok, customer}
    end
  end

  defp render_page(conn, template, assigns) do
    base = %{store: conn.assigns.store, current_customer: conn.assigns.current_customer}

    conn
    |> put_view(html: AlgoieWeb.StorefrontCustomerHTML)
    |> render(template, Map.merge(base, assigns))
  end

  defp context(conn) do
    %{tenant: get_session(conn, "store_tenant"), store_id: get_session(conn, "store_id")}
  end

  defp form(params, name), do: Phoenix.Component.to_form(params, as: name)
  defp error_text(error) when is_binary(error), do: error
  defp error_text(error), do: error |> Ash.Error.to_error_class() |> Exception.message()
end
