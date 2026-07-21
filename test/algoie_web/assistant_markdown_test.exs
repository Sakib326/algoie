defmodule AlgoieWeb.AssistantMarkdownTest do
  use ExUnit.Case, async: true

  alias AlgoieWeb.AssistantMarkdown

  test "renders valid GFM tables" do
    html = AssistantMarkdown.to_html("| Product | Stock |\n|---|---|\n| Tee | 5 |")

    assert html =~ "<table>"
    assert html =~ "<th>Product</th>"
    assert html =~ "<td>Tee</td>"
  end

  test "repairs table rows emitted on one line" do
    markdown =
      "Low stock:\n\n| Product | Stock | |---|---| | Pulse Max | 0 | | Tee | 5 |\n\nRestock soon."

    html = AssistantMarkdown.to_html(markdown)

    assert html =~ "<table>"
    assert html =~ "<td>Pulse Max</td>"
    assert html =~ "<td>Tee</td>"
    assert html =~ "Restock soon."
  end
end
