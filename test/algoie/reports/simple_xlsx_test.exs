defmodule Algoie.Reports.SimpleXLSXTest do
  use ExUnit.Case, async: true

  alias Algoie.Reports.SimpleXLSX

  test "renders a valid styled OpenXML workbook" do
    order = %{
      number: "ORD-1001",
      date: ~U[2026-07-20 10:30:00Z],
      customer: "Demo Customer",
      email: "customer@example.com",
      status: "fulfilled",
      payment: "paid",
      subtotal: Decimal.new("100"),
      discount: Decimal.new("5"),
      shipping: Decimal.new("10"),
      total: Decimal.new("105")
    }

    binary = SimpleXLSX.render("Demo Store", [order])

    assert <<"PK", _::binary>> = binary
    {:ok, files} = :zip.unzip(binary, [:memory])
    names = Enum.map(files, fn {name, _content} -> List.to_string(name) end)
    assert "xl/worksheets/sheet1.xml" in names
    assert "xl/styles.xml" in names

    {_name, sheet} = Enum.find(files, fn {name, _} -> name == ~c"xl/worksheets/sheet1.xml" end)
    assert sheet =~ "Demo Store — Sales Report"
    assert sheet =~ "ORD-1001"
    assert sheet =~ "autoFilter"
  end
end
