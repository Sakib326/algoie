defmodule AlgoieWeb.CustomerLive.Show do
  use AlgoieWeb, :live_view

  require Ash.Query

  alias Algoie.Customers.{Customer, CustomerAddress}
  alias Algoie.Orders.Order

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :customers)
     |> assign(:page_title, "Customer details")
     |> load_customer(id)}
  end

  defp load_customer(socket, id) do
    opts = AlgoieWeb.Scope.opts(socket, page: false)

    case Ash.get(Customer, id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, customer} ->
        addresses =
          read_all(
            CustomerAddress
            |> Ash.Query.filter(customer_id == ^id)
            |> Ash.Query.sort(default?: :desc, inserted_at: :desc),
            opts
          )

        orders =
          read_all(
            Order |> Ash.Query.filter(customer_id == ^id) |> Ash.Query.sort(inserted_at: :desc),
            opts
          )

        total_spent =
          orders
          |> Enum.reject(&(&1.status == :cancelled))
          |> Enum.reduce(Decimal.new(0), &Decimal.add(&1.total_amount, &2))

        socket
        |> assign(:customer, customer)
        |> assign(:addresses, addresses)
        |> assign(:orders, orders)
        |> assign(:total_spent, total_spent)

      _ ->
        socket
        |> assign(:customer, nil)
        |> assign(:addresses, [])
        |> assign(:orders, [])
        |> assign(:total_spent, Decimal.new(0))
    end
  end

  defp read_all(query, opts) do
    case Ash.read(query, opts) do
      {:ok, rows} -> rows
      _ -> []
    end
  end

  defp format_money(amount), do: "৳" <> Decimal.to_string(Decimal.round(amount, 2), :normal)
  defp status_tone(:fulfilled), do: "success"
  defp status_tone(:cancelled), do: "error"
  defp status_tone(:confirmed), do: "primary"
  defp status_tone(_), do: "warning"
  defp humanize(value), do: value |> to_string() |> String.replace("_", " ")
end
