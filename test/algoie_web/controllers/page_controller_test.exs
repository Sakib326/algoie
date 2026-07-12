defmodule AlgoieWeb.PageControllerTest do
  use AlgoieWeb.ConnCase

  test "GET / renders home page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Algoie"
  end
end
