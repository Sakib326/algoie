defmodule Algoie.Reports.SimplePDF do
  @moduledoc "Small dependency-free PDF writer for tabular text reports."

  @page_width 595
  @page_height 842

  def render(title, lines) do
    pages = lines |> Enum.chunk_every(48) |> ensure_page()
    render_pages(pages, &page_content(title, &1, &2, &3))
  end

  def render_sales(store_name, orders) do
    pages = orders |> Enum.chunk_every(27) |> ensure_page()
    render_pages(pages, &sales_page(store_name, orders, &1, &2, &3))
  end

  defp render_pages(pages, content_builder) do
    page_count = length(pages)
    page_refs = for index <- 0..(page_count - 1), do: 4 + index * 2

    objects =
      [
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2,
         "<< /Type /Pages /Kids [#{Enum.map_join(page_refs, " ", &"#{&1} 0 R")}] /Count #{page_count} >>"},
        {3, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"}
      ] ++
        Enum.flat_map(Enum.with_index(pages), fn {page_lines, index} ->
          page_id = 4 + index * 2
          content_id = page_id + 1
          content = content_builder.(page_lines, index + 1, page_count)

          [
            {page_id,
             "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{@page_width} #{@page_height}] /Resources << /Font << /F1 3 0 R >> >> /Contents #{content_id} 0 R >>"},
            {content_id, "<< /Length #{byte_size(content)} >>\nstream\n#{content}\nendstream"}
          ]
        end)

    build_pdf(objects)
  end

  defp sales_page(store_name, all_orders, orders, page, page_count) do
    revenue = Enum.reduce(all_orders, Decimal.new(0), &Decimal.add(&1.total, &2))
    paid = Enum.count(all_orders, &(&1.payment == "paid"))

    average =
      if all_orders == [], do: Decimal.new(0), else: Decimal.div(revenue, length(all_orders))

    rows =
      orders
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {order, index} ->
        y = 555 - index * 18

        background =
          if rem(index, 2) == 0, do: "0.975 0.98 0.99 rg 28 #{y - 5} 539 18 re f\n", else: ""

        background <>
          text(34, y, 7.2, order.number, "0.12 0.14 0.2") <>
          text(133, y, 7.2, Calendar.strftime(order.date, "%d %b %Y"), "0.35 0.38 0.45") <>
          text(205, y, 7.2, truncate(order.customer, 23), "0.12 0.14 0.2") <>
          text(342, y, 7.2, humanize(order.status), status_color(order.status)) <>
          text(414, y, 7.2, humanize(order.payment), "0.35 0.38 0.45") <>
          right_text(
            560,
            y,
            7.2,
            "BDT #{Decimal.to_string(order.total, :normal)}",
            "0.12 0.14 0.2"
          )
      end)

    """
    0.97 0.975 0.985 rg 0 0 595 842 re f
    0.075 0.09 0.17 rg 0 682 595 160 re f
    0.31 0.27 0.9 rg 28 796 34 5 re f
    #{text(28, 765, 22, store_name, "1 1 1")}
    #{text(28, 740, 10, "Sales performance report", "0.72 0.75 0.84")}
    #{right_text(565, 765, 8, Calendar.strftime(Date.utc_today(), "%d %b %Y"), "0.72 0.75 0.84")}
    1 1 1 rg 28 602 128 62 re f
    1 1 1 rg 165 602 128 62 re f
    1 1 1 rg 302 602 128 62 re f
    1 1 1 rg 439 602 128 62 re f
    #{text(40, 644, 7, "GROSS REVENUE", "0.45 0.48 0.55")}
    #{text(40, 620, 13, "BDT #{Decimal.to_string(Decimal.round(revenue, 2), :normal)}", "0.12 0.14 0.2")}
    #{text(177, 644, 7, "TOTAL ORDERS", "0.45 0.48 0.55")}
    #{text(177, 620, 13, to_string(length(all_orders)), "0.12 0.14 0.2")}
    #{text(314, 644, 7, "AVERAGE ORDER", "0.45 0.48 0.55")}
    #{text(314, 620, 13, "BDT #{Decimal.to_string(Decimal.round(average, 2), :normal)}", "0.12 0.14 0.2")}
    #{text(451, 644, 7, "PAID ORDERS", "0.45 0.48 0.55")}
    #{text(451, 620, 13, to_string(paid), "0.12 0.14 0.2")}
    0.31 0.27 0.9 rg 28 568 539 24 re f
    #{text(34, 577, 7, "ORDER", "1 1 1")}
    #{text(133, 577, 7, "DATE", "1 1 1")}
    #{text(205, 577, 7, "CUSTOMER", "1 1 1")}
    #{text(342, 577, 7, "STATUS", "1 1 1")}
    #{text(414, 577, 7, "PAYMENT", "1 1 1")}
    #{right_text(560, 577, 7, "TOTAL", "1 1 1")}
    #{rows}
    #{text(28, 25, 7, "Algoie · Confidential sales report", "0.5 0.53 0.6")}
    #{right_text(565, 25, 7, "Page #{page} of #{page_count}", "0.5 0.53 0.6")}
    """
  end

  defp ensure_page([]), do: [[]]
  defp ensure_page(pages), do: pages

  defp page_content(title, lines, page, pages) do
    header = [
      title,
      "Generated #{DateTime.utc_now() |> Calendar.strftime("%d %b %Y %H:%M UTC")}",
      ""
    ]

    footer = "Page #{page} of #{pages}"

    commands =
      (header ++ lines)
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {line, index} ->
        size = if index == 0, do: 15, else: 8
        y = 805 - index * 15
        "BT /F1 #{size} Tf 32 #{y} Td (#{escape(line)}) Tj ET"
      end)

    commands <> "\nBT /F1 8 Tf 500 20 Td (#{footer}) Tj ET"
  end

  defp text(x, y, size, value, color) do
    "#{color} rg BT /F1 #{size} Tf #{x} #{y} Td (#{escape(value)}) Tj ET\n"
  end

  defp right_text(x, y, size, value, color) do
    width = String.length(to_string(value)) * size * 0.48
    text(Float.round(x - width, 2), y, size, value, color)
  end

  defp truncate(value, length) do
    value = to_string(value)
    if String.length(value) > length, do: String.slice(value, 0, length - 1) <> "…", else: value
  end

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp status_color("fulfilled"), do: "0.02 0.5 0.35"
  defp status_color("cancelled"), do: "0.8 0.15 0.2"
  defp status_color("confirmed"), do: "0.25 0.25 0.75"
  defp status_color(_), do: "0.65 0.4 0.05"

  defp build_pdf(objects) do
    header = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n"

    {body, offsets} =
      Enum.reduce(objects, {"", []}, fn {id, content}, {body, offsets} ->
        object = "#{id} 0 obj\n#{content}\nendobj\n"
        {body <> object, offsets ++ [byte_size(header) + byte_size(body)]}
      end)

    xref_offset = byte_size(header) + byte_size(body)
    count = length(objects) + 1

    entries =
      "0000000000 65535 f \n" <>
        Enum.map_join(
          offsets,
          "",
          &(:io_lib.format("~10..0B 00000 n \n", [&1]) |> IO.iodata_to_binary())
        )

    trailer =
      "xref\n0 #{count}\n#{entries}trailer\n<< /Size #{count} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"

    header <> body <> trailer
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace(~r/[^\x20-\x7E]/u, "?")
  end
end
