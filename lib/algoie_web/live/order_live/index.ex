defmodule AlgoieWeb.OrderLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Orders.Order

  @statuses [:pending, :pre_order, :confirmed, :fulfilled, :cancelled]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :orders)
     |> assign(:filter, "all")
     |> assign(:customer_map, load_customer_map(socket))
     |> load_orders()}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Orders")}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:filter, status) |> apply_filter()}
  end

  defp load_orders(socket) do
    orders =
      case Ash.read(Order, AlgoieWeb.Scope.opts(socket)) do
        {:ok, orders} -> Enum.sort_by(orders, & &1.inserted_at, {:desc, DateTime})
        _ -> []
      end

    socket
    |> assign(:all_orders, orders)
    |> apply_filter()
  end

  defp load_customer_map(socket) do
    case Ash.read(Algoie.Customers.Customer, AlgoieWeb.Scope.opts(socket)) do
      {:ok, customers} -> Map.new(customers, &{&1.id, &1.name})
      _ -> %{}
    end
  end

  defp apply_filter(socket) do
    filter = socket.assigns.filter
    all = socket.assigns.all_orders

    orders =
      if filter == "all" do
        all
      else
        Enum.filter(all, &(to_string(&1.status) == filter))
      end

    assign(socket, :orders, orders)
  end

  defp filters, do: [{"all", "All"} | Enum.map(@statuses, &{to_string(&1), humanize(&1)})]

  defp count_for(orders, "all"), do: length(orders)
  defp count_for(orders, status), do: Enum.count(orders, &(to_string(&1.status) == status))

  defp status_tone(:pending), do: "warning"
  defp status_tone(:pre_order), do: "info"
  defp status_tone(:confirmed), do: "primary"
  defp status_tone(:fulfilled), do: "success"
  defp status_tone(:cancelled), do: "error"
  defp status_tone(_), do: "neutral"

  defp humanize(status), do: status |> to_string() |> String.replace("_", " ")

  defp short_id(id), do: id |> to_string() |> String.slice(0, 8)

  defp format_money(%Decimal{} = amount) do
    "$" <> (amount |> Decimal.round(2) |> Decimal.to_string(:normal))
  end

  defp format_money(_), do: "$0.00"
end
