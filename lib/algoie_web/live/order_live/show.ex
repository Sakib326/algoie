defmodule AlgoieWeb.OrderLive.Show do
  use AlgoieWeb, :live_view

  alias Algoie.Orders.Order
  require Ash.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(:active, :orders) |> load_order(id)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Order Details")}
  end

  @impl true
  def handle_event("update_status", %{"status" => new_status}, socket) do
    case parse_status(new_status) do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid status")}

      status_atom ->
        changeset =
          Ash.Changeset.for_update(socket.assigns.order, :update_status, %{status: status_atom})

        case Ash.update(changeset, AlgoieWeb.Scope.opts(socket)) do
          {:ok, order} ->
            Algoie.Notifications.order_status_changed(order, socket.assigns.store_name, %{
              tenant: socket.assigns.tenant,
              store_id: socket.assigns.store_id
            })

            {:noreply,
             socket
             |> assign(:order, order)
             |> put_flash(:info, "Order status updated to #{status_atom}")}

          {:error, changeset} ->
            error_msg =
              changeset.errors
              |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
              |> Enum.join(", ")

            {:noreply, put_flash(socket, :error, "Failed to update status: #{error_msg}")}
        end
    end
  end

  def handle_event("update_payment_status", %{"payment" => %{"status" => new_status}}, socket) do
    case parse_payment_status(new_status) do
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid payment status")}

      payment_status ->
        changeset =
          Ash.Changeset.for_update(socket.assigns.order, :update_payment_status, %{
            payment_status: payment_status
          })

        case Ash.update(changeset, AlgoieWeb.Scope.opts(socket)) do
          {:ok, order} ->
            delivery_result =
              Algoie.Notifications.payment_status_changed(order, socket.assigns.store_name, %{
                tenant: socket.assigns.tenant,
                store_id: socket.assigns.store_id
              })

            {flash_type, message} = payment_flash(delivery_result, payment_status)

            {:noreply,
             socket
             |> assign(:order, order)
             |> put_flash(flash_type, message)}

          {:error, error} ->
            {:noreply,
             put_flash(socket, :error, "Payment status was not updated: #{error_text(error)}")}
        end
    end
  end

  defp parse_status("pending"), do: :pending
  defp parse_status("pre_order"), do: :pre_order
  defp parse_status("confirmed"), do: :confirmed
  defp parse_status("fulfilled"), do: :fulfilled
  defp parse_status("cancelled"), do: :cancelled
  defp parse_status(_), do: nil

  defp parse_payment_status("pending"), do: :pending
  defp parse_payment_status("paid"), do: :paid
  defp parse_payment_status("failed"), do: :failed
  defp parse_payment_status("refunded"), do: :refunded
  defp parse_payment_status(_), do: nil

  defp load_order(socket, id) do
    case Ash.get(Order, id, AlgoieWeb.Scope.opts(socket)) do
      {:ok, order} ->
        line_items =
          case Algoie.Orders.OrderLineItem
               |> Ash.Query.filter(order_id == ^order.id)
               |> Ash.Query.for_read(:read)
               |> Ash.read(
                 tenant: socket.assigns.tenant,
                 actor: socket.assigns[:current_user],
                 page: false
               ) do
            {:ok, items} -> items
            _ -> []
          end

        customer =
          case Ash.get(Algoie.Customers.Customer, order.customer_id, AlgoieWeb.Scope.opts(socket)) do
            {:ok, c} -> c
            _ -> nil
          end

        socket
        |> assign(:order, order)
        |> assign(:customer, customer)
        |> assign(:line_items, line_items)

      _ ->
        socket
        |> assign(:order, nil)
        |> assign(:customer, nil)
        |> assign(:line_items, [])
    end
  end

  defp allowed_next_statuses(:pending), do: [:pre_order, :confirmed, :cancelled]
  defp allowed_next_statuses(:pre_order), do: [:confirmed, :cancelled]
  defp allowed_next_statuses(:confirmed), do: [:fulfilled, :cancelled]
  defp allowed_next_statuses(_), do: []

  defp allowed_payment_statuses(:pending), do: [:paid, :failed]
  defp allowed_payment_statuses(:failed), do: [:paid]
  defp allowed_payment_statuses(:paid), do: [:refunded]
  defp allowed_payment_statuses(_), do: []

  defp payment_tone(:paid), do: "success"
  defp payment_tone(:pending), do: "warning"
  defp payment_tone(:failed), do: "error"
  defp payment_tone(:refunded), do: "info"
  defp payment_tone(_), do: "neutral"

  defp payment_flash({:ok, _metadata}, status),
    do: {:info, "Payment marked #{status}. Customer notification sent."}

  defp payment_flash(:skipped, status),
    do: {:info, "Payment marked #{status}. No customer email was available."}

  defp payment_flash({:error, reason}, status),
    do: {:error, "Payment marked #{status}, but the email failed: #{error_text(reason)}"}

  defp error_text(error) when is_binary(error), do: error
  defp error_text(error), do: inspect(error)

  defp status_tone(:pending), do: "warning"
  defp status_tone(:pre_order), do: "info"
  defp status_tone(:confirmed), do: "primary"
  defp status_tone(:fulfilled), do: "success"
  defp status_tone(:cancelled), do: "error"
  defp status_tone(_), do: "neutral"

  defp humanize(status), do: status |> to_string() |> String.replace("_", " ")

  defp short_id(id), do: id |> to_string() |> String.slice(0, 8)

  defp format_money(%Decimal{} = amount) do
    "৳" <> (amount |> Decimal.round(2) |> Decimal.to_string(:normal))
  end

  defp format_money(_), do: "৳0.00"
end
