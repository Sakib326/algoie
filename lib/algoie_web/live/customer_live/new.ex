defmodule AlgoieWeb.CustomerLive.New do
  use AlgoieWeb, :live_view

  alias Algoie.Customers.{Customer, CustomerAddress}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :customers)
     |> assign(:page_title, "Add customer")
     |> assign_form(%{})}
  end

  @impl true
  def handle_event("validate", %{"customer" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("save", %{"customer" => params}, socket) do
    result =
      Algoie.Repo.transaction(fn ->
        with {:ok, customer} <- create_customer(socket, params),
             {:ok, _address} <- maybe_create_address(socket, customer, params) do
          customer
        else
          {:error, error} -> Algoie.Repo.rollback(error)
        end
      end)

    case result do
      {:ok, customer} ->
        {:noreply,
         socket
         |> put_flash(:info, "Customer #{customer.name} created")
         |> push_navigate(to: ~p"/dashboard/customers/#{customer.id}")}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_form(params)
         |> put_flash(:error, error_message(error))}
    end
  end

  defp create_customer(socket, params) do
    Customer
    |> Ash.Changeset.for_create(:create, %{
      store_id: socket.assigns.store_id,
      name: blank_to_nil(params["name"]),
      email: blank_to_nil(params["email"]),
      phone: blank_to_nil(params["phone"])
    })
    |> Ash.create(AlgoieWeb.Scope.opts(socket))
  end

  defp maybe_create_address(_socket, _customer, %{"add_address" => value})
       when value not in ["true", true],
       do: {:ok, nil}

  defp maybe_create_address(socket, customer, params) do
    CustomerAddress
    |> Ash.Changeset.for_create(:create, %{
      customer_id: customer.id,
      store_id: socket.assigns.store_id,
      label: blank_to_nil(params["label"]) || "Delivery address",
      recipient_name: blank_to_nil(params["recipient_name"]) || customer.name,
      phone: blank_to_nil(params["delivery_phone"]) || customer.phone,
      address_line1: blank_to_nil(params["address_line1"]),
      address_line2: blank_to_nil(params["address_line2"]),
      area: blank_to_nil(params["area"]),
      city: blank_to_nil(params["city"]),
      postal_code: blank_to_nil(params["postal_code"]),
      country: blank_to_nil(params["country"]) || "Bangladesh",
      default?: true
    })
    |> Ash.create(AlgoieWeb.Scope.opts(socket))
  end

  defp assign_form(socket, params) do
    defaults = %{"add_address" => "false", "country" => "Bangladesh"}
    params = Map.merge(defaults, params)

    socket
    |> assign(:form, to_form(params, as: :customer))
    |> assign(:add_address?, params["add_address"] in ["true", true])
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil

  defp blank_to_nil(value),
    do: value |> to_string() |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))

  defp error_message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Exception.message()
  rescue
    _ -> "Could not create the customer. Check the required fields and try again."
  end
end
