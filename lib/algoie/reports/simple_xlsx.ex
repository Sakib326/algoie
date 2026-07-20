defmodule Algoie.Reports.SimpleXLSX do
  @moduledoc "Dependency-free OpenXML workbook writer for sales exports."

  def render(store_name, rows) do
    files = [
      {~c"[Content_Types].xml", content_types()},
      {~c"_rels/.rels", root_relationships()},
      {~c"docProps/app.xml", app_properties()},
      {~c"docProps/core.xml", core_properties()},
      {~c"xl/workbook.xml", workbook()},
      {~c"xl/_rels/workbook.xml.rels", workbook_relationships()},
      {~c"xl/styles.xml", styles()},
      {~c"xl/worksheets/sheet1.xml", worksheet(store_name, rows)}
    ]

    {:ok, {_name, binary}} = :zip.create(~c"sales-report.xlsx", files, [:memory])
    binary
  end

  defp worksheet(store_name, rows) do
    revenue = Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.total, &2))
    paid = Enum.count(rows, &(&1.payment == "paid"))
    average = if rows == [], do: Decimal.new(0), else: Decimal.div(revenue, length(rows))

    data_rows =
      rows
      |> Enum.with_index(8)
      |> Enum.map_join("", fn {row, index} ->
        style = if rem(index, 2) == 0, do: 4, else: 3

        xml_row(index, [
          text_cell("A#{index}", row.number, style),
          text_cell("B#{index}", Calendar.strftime(row.date, "%Y-%m-%d %H:%M"), style),
          text_cell("C#{index}", row.customer, style),
          text_cell("D#{index}", row.email || "", style),
          text_cell("E#{index}", humanize(row.status), style),
          text_cell("F#{index}", humanize(row.payment), style),
          number_cell("G#{index}", row.subtotal, 5),
          number_cell("H#{index}", row.discount, 5),
          number_cell("I#{index}", row.shipping, 5),
          number_cell("J#{index}", row.total, 6)
        ])
      end)

    last_row = max(length(rows) + 7, 8)

    xml("""
    <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <sheetViews><sheetView workbookViewId="0"><pane ySplit="7" topLeftCell="A8" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
      <cols><col min="1" max="1" width="21" customWidth="1"/><col min="2" max="2" width="20" customWidth="1"/><col min="3" max="3" width="24" customWidth="1"/><col min="4" max="4" width="30" customWidth="1"/><col min="5" max="6" width="15" customWidth="1"/><col min="7" max="10" width="15" customWidth="1"/></cols>
      <sheetData>
        #{xml_row(1, [text_cell("A1", store_name <> " — Sales Report", 1)])}
        #{xml_row(2, [text_cell("A2", "Generated " <> Calendar.strftime(DateTime.utc_now(), "%d %b %Y, %H:%M UTC"), 2)])}
        #{xml_row(4, [text_cell("A4", "Gross revenue", 7), number_cell("B4", revenue, 8), text_cell("D4", "Orders", 7), number_cell("E4", length(rows), 8), text_cell("G4", "Paid orders", 7), number_cell("H4", paid, 8)])}
        #{xml_row(5, [text_cell("A5", "Average order", 7), number_cell("B5", average, 8)])}
        #{xml_row(7, Enum.with_index(["Order", "Date", "Customer", "Email", "Status", "Payment", "Subtotal", "Discount", "Shipping", "Total"], 1) |> Enum.map(fn {value, column} -> text_cell("#{column_name(column)}7", value, 2) end))}
        #{data_rows}
      </sheetData>
      <autoFilter ref="A7:J#{last_row}"/>
      <mergeCells count="2"><mergeCell ref="A1:J1"/><mergeCell ref="A2:J2"/></mergeCells>
      <pageMargins left="0.25" right="0.25" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>
    </worksheet>
    """)
  end

  defp xml_row(index, cells), do: "<row r=\"#{index}\">#{Enum.join(cells)}</row>"

  defp text_cell(reference, value, style) do
    ~s(<c r="#{reference}" t="inlineStr" s="#{style}"><is><t xml:space="preserve">#{escape(value)}</t></is></c>)
  end

  defp number_cell(reference, %Decimal{} = value, style),
    do: ~s(<c r="#{reference}" s="#{style}"><v>#{Decimal.to_string(value, :normal)}</v></c>)

  defp number_cell(reference, value, style),
    do: ~s(<c r="#{reference}" s="#{style}"><v>#{value}</v></c>)

  defp styles do
    xml("""
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="4"><font><sz val="11"/><name val="Aptos"/></font><font><b/><sz val="20"/><color rgb="FFFFFFFF"/><name val="Aptos Display"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font><font><b/><sz val="11"/><color rgb="FF111827"/><name val="Aptos"/></font></fonts>
      <fills count="6"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF312E81"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF4F46E5"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF8FAFC"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEEF2FF"/><bgColor indexed="64"/></patternFill></fill></fills>
      <borders count="2"><border/><border><bottom style="thin"><color rgb="FFE5E7EB"/></bottom></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="9"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/><xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/><xf numFmtId="4" fontId="3" fillId="5" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/><xf numFmtId="0" fontId="0" fillId="5" borderId="0" xfId="0" applyFill="1"/><xf numFmtId="4" fontId="3" fillId="5" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/></cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """)
  end

  defp content_types,
    do:
      xml(
        ~S(<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>)
      )

  defp root_relationships,
    do:
      xml(
        ~S(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>)
      )

  defp workbook,
    do:
      xml(
        ~S(<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sales" sheetId="1" r:id="rId1"/></sheets></workbook>)
      )

  defp workbook_relationships,
    do:
      xml(
        ~S(<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>)
      )

  defp app_properties,
    do:
      xml(
        ~S(<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Algoie</Application></Properties>)
      )

  defp core_properties,
    do:
      xml(
        ~S(<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Algoie</dc:creator><dc:title>Sales Report</dc:title></cp:coreProperties>)
      )

  defp xml(content), do: ~s(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>#{content})
  defp column_name(index), do: <<64 + index>>

  defp humanize(value),
    do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
