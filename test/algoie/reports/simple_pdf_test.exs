defmodule Algoie.Reports.SimplePDFTest do
  use ExUnit.Case, async: true

  alias Algoie.Reports.SimplePDF

  test "renders a valid multi-page PDF document" do
    binary = SimplePDF.render("Sales Report", Enum.map(1..100, &"Order #{&1}"))

    assert binary =~ "%PDF-1.4"
    assert binary =~ "/Type /Catalog"
    assert binary =~ "/Count 3"
    assert binary =~ "xref"
    assert binary =~ "%%EOF"
  end

  test "renders a branded sales PDF with metrics and order rows" do
    order = %{
      number: "ORD-1001",
      date: ~U[2026-07-20 10:30:00Z],
      customer: "Demo Customer",
      status: "fulfilled",
      payment: "paid",
      total: Decimal.new("105")
    }

    binary = SimplePDF.render_sales("Demo Store", [order])

    assert binary =~ "Demo Store"
    assert binary =~ "GROSS REVENUE"
    assert binary =~ "ORD-1001"
    assert binary =~ "0.31 0.27 0.9 rg"
  end
end
