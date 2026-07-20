defmodule AlgoieWeb.LoginLiveTest do
  use AlgoieWeb.ConnCase, async: true

  test "submits only inputs accepted by the password strategy", %{conn: conn} do
    html =
      conn
      |> get(~p"/sign-in")
      |> html_response(200)

    assert html =~ ~s(name="user[email]")
    assert html =~ ~s(name="user[password]")
    refute html =~ "remember_me"
  end
end
