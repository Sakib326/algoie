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
