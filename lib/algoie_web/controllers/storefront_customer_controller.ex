defmodule AlgoieWeb.StorefrontCustomerController do
  use AlgoieWeb, :controller

  require Ash.Query

  alias Algoie.Customers.CustomerAddress
  alias Algoie.Orders.{Order, OrderLineItem}
  alias Algoie.Storefront.CustomerAccounts

  def register(conn, _params) do
    if conn.assigns.current_customer,
      do: redirect(conn, to: ~p"/account"),
      else: render_page(conn, :register, %{form: form(%{}, :registration), otp_pending: false})
  end

  def create_account(conn, %{"registration" => params}) do
    context = context(conn)

    if blank?(params["otp_code"]) do
      request_customer_registration_code(conn, context, params)
    else
      verify_and_create_customer(conn, context, params)
    end
  end

  def forgot_password(conn, _params) do
    render_page(conn, :forgot_password, %{form: form(%{}, :reset), code_sent: false})
  end

  def request_password_reset(conn, %{"reset" => %{"email" => email}}) do
    context = context(conn)
    _ = CustomerAccounts.request_password_reset(context.tenant, context.store_id, email)

    conn
    |> put_flash(:info, "If that account exists, a verification code has been sent.")
    |> render_page(:forgot_password, %{
      code_sent: true,
      form: form(%{"email" => email}, :reset)
    })
  end

  def reset_password(conn, %{"reset" => params}) do
    context = context(conn)

    case CustomerAccounts.reset_password(
           context.tenant,
           context.store_id,
           params["email"],
           params["otp_code"],
           params["password"],
           params["password_confirmation"]
         ) do
      :ok ->
        conn
        |> put_flash(:info, "Password updated. You can now sign in.")
        |> redirect(to: ~p"/account/sign-in")

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, otp_error(reason))
        |> render_page(:forgot_password, %{code_sent: true, form: form(params, :reset)})
    end
  end

  defp verify_and_create_customer(conn, context, params) do
    with :ok <- CustomerAccounts.validate_registration_input(params),
         :ok <-
           CustomerAccounts.verify_registration_code(
             context.tenant,
             context.store_id,
             params["email"],
             params["otp_code"]
           ) do
      create_verified_customer(conn, context, params)
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, otp_error(reason))
        |> render_page(:register, %{form: form(params, :registration), otp_pending: true})
    end
  end

  defp create_verified_customer(conn, context, params) do
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
        |> render_page(:register, %{form: form(params, :registration), otp_pending: true})
    end
  end

  defp request_customer_registration_code(conn, context, params) do
    with :ok <- CustomerAccounts.validate_registration_input(params),
         :ok <-
           CustomerAccounts.request_registration_code(
             context.tenant,
             context.store_id,
             params["email"]
           ) do
      safe_params =
        params
        |> Map.put("password", "")
        |> Map.put("password_confirmation", "")

      conn
      |> put_flash(:info, "We sent a 6-digit verification code to #{params["email"]}")
      |> render_page(:register, %{
        form: form(safe_params, :registration),
        otp_pending: true
      })
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, otp_error(reason))
        |> render_page(:register, %{form: form(params, :registration), otp_pending: false})
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
  defp blank?(value), do: String.trim(value || "") == ""

  defp otp_error(:rate_limited), do: "Please wait a minute before requesting another code"
  defp otp_error(:expired_code), do: "The verification code expired. Request a new code."
  defp otp_error(:too_many_attempts), do: "Too many incorrect attempts. Request a new code."
  defp otp_error(:invalid_code), do: "The verification code is incorrect."
  defp otp_error(message) when is_binary(message), do: message
  defp otp_error(error), do: error_text(error)
  defp error_text(error) when is_binary(error), do: error
  defp error_text(error), do: error |> Ash.Error.to_error_class() |> Exception.message()
end
