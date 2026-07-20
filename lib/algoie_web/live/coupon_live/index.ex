defmodule AlgoieWeb.CouponLive.Index do
  use AlgoieWeb, :live_view

  require Ash.Query
  alias Algoie.Customers.Coupon

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active, :coupons)
     |> assign(:page_title, "Coupons")
     |> assign(:page, 1)
     |> assign_form(%{})
     |> load_coupons()}
  end

  @impl true
  def handle_event("validate", %{"coupon" => params}, socket),
    do: {:noreply, assign_form(socket, params)}

  def handle_event("save", %{"coupon" => params}, socket) do
    attrs = %{
      store_id: socket.assigns.store_id,
      code: params["code"],
      discount_type: parse_type(params["discount_type"]),
      discount_value: params["discount_value"],
      min_order_value: blank_to_nil(params["min_order_value"]),
      usage_limit: parse_optional_integer(params["usage_limit"]),
      starts_at: parse_datetime(params["starts_at"]),
      expires_at: parse_datetime(params["expires_at"]),
      active?: true
    }

    result =
      Coupon
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create(AlgoieWeb.Scope.opts(socket))

    case result do
      {:ok, _coupon} ->
        {:noreply,
         socket |> assign_form(%{}) |> load_coupons() |> put_flash(:info, "Coupon created")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    with {:ok, coupon} <- Ash.get(Coupon, id, AlgoieWeb.Scope.opts(socket)),
         {:ok, _} <-
           coupon
           |> Ash.Changeset.for_update(:update, %{active?: !coupon.active?})
           |> Ash.update(AlgoieWeb.Scope.opts(socket)) do
      {:noreply, load_coupons(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not update coupon")}
    end
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, socket |> assign(:page, parse_page(page)) |> load_coupons()}
  end

  defp load_coupons(socket) do
    case Ash.read(
           Coupon |> Ash.Query.sort(inserted_at: :desc),
           AlgoieWeb.Scope.opts(socket, page: false)
         ) do
      {:ok, coupons} ->
        page_size = 10
        page_count = max(ceil(length(coupons) / page_size), 1)
        page = min(socket.assigns.page, page_count)

        socket
        |> assign(:coupons, Enum.slice(coupons, (page - 1) * page_size, page_size))
        |> assign(:page, page)
        |> assign(:page_count, page_count)

      _ ->
        socket |> assign(:coupons, []) |> assign(:page_count, 1)
    end
  end

  defp assign_form(socket, params) do
    defaults = %{"discount_type" => "percent"}
    assign(socket, :form, to_form(Map.merge(defaults, params), as: :coupon))
  end

  defp parse_type("fixed"), do: :fixed
  defp parse_type(_), do: :percent
  defp parse_optional_integer(value) when value in [nil, ""], do: nil

  defp parse_optional_integer(value) do
    case Integer.parse(value) do
      {integer, _} -> integer
      _ -> nil
    end
  end

  defp parse_datetime(value) when value in [nil, ""], do: nil

  defp parse_datetime(value) do
    case NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok, datetime} -> DateTime.from_naive!(datetime, "Etc/UTC")
      _ -> nil
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
  defp error_text(error), do: error |> Ash.Error.to_error_class() |> Exception.message()
  defp format_money(nil), do: "—"
  defp format_money(amount), do: "৳" <> Decimal.to_string(Decimal.round(amount, 2), :normal)

  defp discount_label(%{discount_type: :percent, discount_value: value}),
    do: Decimal.to_string(value, :normal) <> "%"

  defp discount_label(%{discount_value: value}), do: format_money(value)

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
