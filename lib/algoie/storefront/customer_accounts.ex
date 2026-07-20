defmodule Algoie.Storefront.CustomerAccounts do
  @moduledoc "Tenant and store-scoped customer account operations."

  require Ash.Query

  alias Algoie.Customers.Customer

  def register(tenant, store_id, params) do
    email = normalize_email(params["email"])

    with :ok <- validate_registration(params, email) do
      case find_by_email(tenant, store_id, email) do
        nil ->
          Customer
          |> Ash.Changeset.for_create(
            :register,
            %{
              store_id: store_id,
              name: String.trim(params["name"]),
              email: email,
              phone: blank_to_nil(params["phone"]),
              password: params["password"]
            },
            tenant: tenant
          )
          |> Ash.create(authorize?: false)

        customer ->
          customer
          |> Ash.Changeset.for_update(
            :register_existing,
            %{
              name: String.trim(params["name"]),
              phone: blank_to_nil(params["phone"]),
              password: params["password"]
            },
            tenant: tenant
          )
          |> Ash.update(authorize?: false)
      end
    end
  end

  def validate_registration_input(params) do
    validate_registration(params, normalize_email(params["email"]))
  end

  def authenticate(tenant, store_id, email, password) do
    customer = find_by_email(tenant, store_id, normalize_email(email))

    if customer && customer.hashed_password &&
         Bcrypt.verify_pass(password || "", customer.hashed_password),
       do: {:ok, customer},
       else: {:error, :invalid_credentials}
  end

  def get(tenant, store_id, id) do
    Customer
    |> Ash.Query.filter(id == ^id and store_id == ^store_id and not is_nil(hashed_password))
    |> Ash.read_one(tenant: tenant, authorize?: false)
  end

  def request_registration_code(tenant, store_id, email) do
    issue_code(email, :customer_registration, otp_context(tenant, store_id))
  end

  def verify_registration_code(tenant, store_id, email, code) do
    Algoie.Accounts.EmailOtp.verify(
      email,
      :customer_registration,
      otp_context(tenant, store_id),
      code
    )
  end

  def request_password_reset(tenant, store_id, email) do
    normalized = normalize_email(email)

    if find_by_email(tenant, store_id, normalized) do
      issue_code(normalized, :customer_password_reset, otp_context(tenant, store_id))
    else
      :ok
    end
  end

  def reset_password(tenant, store_id, email, code, password, confirmation) do
    normalized = normalize_email(email)

    with true <- String.length(password || "") >= 8,
         true <- password == confirmation,
         :ok <-
           Algoie.Accounts.EmailOtp.verify(
             normalized,
             :customer_password_reset,
             otp_context(tenant, store_id),
             code
           ),
         %Customer{} = customer <- find_by_email(tenant, store_id, normalized),
         {:ok, _customer} <-
           Ash.update(customer, %{password: password},
             action: :reset_password,
             tenant: tenant,
             authorize?: false
           ) do
      :ok
    else
      false -> {:error, "Passwords must match and contain at least 8 characters"}
      nil -> {:error, :invalid_code}
      {:error, reason} -> {:error, reason}
    end
  end

  defp issue_code(email, purpose, context) do
    case Algoie.Accounts.EmailOtp.issue(email, purpose, context) do
      {:ok, code} -> Algoie.Notifications.verification_code(email, code, purpose)
      {:error, :rate_limited} -> {:error, :rate_limited}
      {:error, error} -> {:error, error}
    end
  end

  defp otp_context(tenant, store_id), do: "#{tenant}:#{store_id}"

  defp find_by_email(_tenant, _store_id, nil), do: nil

  defp find_by_email(tenant, store_id, email) do
    Customer
    |> Ash.Query.filter(store_id == ^store_id and email == ^email)
    |> Ash.read_one!(tenant: tenant, authorize?: false)
  end

  defp validate_registration(params, email) do
    cond do
      String.trim(params["name"] || "") == "" ->
        {:error, "Name is required"}

      is_nil(email) ->
        {:error, "Email is required"}

      String.length(params["password"] || "") < 8 ->
        {:error, "Password must be at least 8 characters"}

      params["password"] != params["password_confirmation"] ->
        {:error, "Passwords do not match"}

      true ->
        :ok
    end
  end

  defp normalize_email(value) do
    case blank_to_nil(value) do
      nil -> nil
      email -> String.downcase(email)
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))
end
