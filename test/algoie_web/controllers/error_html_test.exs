defmodule AlgoieWeb.ErrorHTMLTest do
  use AlgoieWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(AlgoieWeb.ErrorHTML, "404", "html", [])
    assert html =~ "404"
    assert html =~ "Page Not Found"
  end

  test "renders 500.html" do
    html = render_to_string(AlgoieWeb.ErrorHTML, "500", "html", [])
    assert html =~ "500"
    assert html =~ "Something Went Wrong"
  end
end
