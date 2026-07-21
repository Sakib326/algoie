defmodule AlgoieWeb.AssistantMarkdown do
  @moduledoc "Renders assistant Markdown with resilient result-table support."

  @extensions [table: true, strikethrough: true, tasklist: true]

  def to_html(content) when is_binary(content) do
    content
    |> normalize_inline_table_rows()
    |> MDEx.to_html!(extension: @extensions)
  end

  defp normalize_inline_table_rows(content) do
    String.replace(content, ~r/\|\h+\|(?=\h*(?:\:?-{3,}|[^\s|]))/u, "|\n|")
  end
end
