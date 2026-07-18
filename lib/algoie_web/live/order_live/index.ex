defmodule AlgoieWeb.OrderLive.Index do
  use AlgoieWeb, :live_view

  alias Algoie.Orders.Order
  require Ash.Query

  @statuses [:pending, :pre_order, :confirmed, :fulfilled, :cancelled]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :orders)
     |> assign(:filter, "all")
     |> assign(:page, 1)
     |> assign(:orders_page, nil)
     |> assign(:counts, %{})
     |> assign(:customer_map, load_customer_map(socket))
     |> load_counts()
     |> load_orders()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page =
      case Integer.parse(params["page"] || "1") do
        {p, _} when p > 0 -> p
        _ -> 1
      end

    socket =
      socket
      |> assign(:page, page)
      |> assign(:page_title, "Orders")
      |> load_orders()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:filter, status) |> assign(:page, 1) |> load_orders()}
  end

  defp load_orders(socket) do
    limit = 12
    offset = (socket.assigns.page - 1) * limit
    
    query = Order |> Ash.Query.sort(inserted_at: :desc)
    
    query = 
      if socket.assigns.filter != "all" do
        Ash.Query.filter(query, status == ^String.to_existing_atom(socket.assigns.filter))
      else
        query
      end
      
    opts = Keyword.put(AlgoieWeb.Scope.opts(socket), :page, offset: offset, count: true)

    case Ash.read(query, opts) do
      {:ok, page_result} -> 
        socket
        |> assign(:orders, page_result.results)
        |> assign(:orders_page, page_result)
      _ -> 
        socket
        |> assign(:orders, [])
        |> assign(:orders_page, nil)
    end
  end

  defp load_customer_map(socket) do
    opts = Keyword.put(AlgoieWeb.Scope.opts(socket), :page, false)
    case Ash.read(Algoie.Customers.Customer, opts) do
      {:ok, customers} -> Map.new(customers, &{&1.id, &1.name})
      _ -> %{}
    end
  end

  defp load_counts(socket) do
    opts = Keyword.put(AlgoieWeb.Scope.opts(socket), :page, false)
    case Ash.read(Order |> Ash.Query.select([:status]), opts) do
      {:ok, orders} ->
        counts = Enum.frequencies_by(orders, &(to_string(&1.status)))
        counts = Map.put(counts, "all", length(orders))
        assign(socket, :counts, counts)
      _ ->
        assign(socket, :counts, %{"all" => 0})
    end
  end

  defp filters, do: [{"all", "All"} | Enum.map(@statuses, &{to_string(&1), humanize(&1)})]

  defp count_for(counts, status), do: Map.get(counts, status, 0)

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
