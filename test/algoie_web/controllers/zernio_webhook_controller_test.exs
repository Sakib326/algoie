defmodule AlgoieWeb.ZernioWebhookControllerTest do
  use AlgoieWeb.ConnCase, async: false

  alias Algoie.{Repo, SocialPublishingSetting}
  alias Algoie.SocialPublishing.WebhookReceipt

  setup do
    Repo.delete_all(WebhookReceipt)
    Repo.delete_all(SocialPublishingSetting)
    {:ok, _settings} = SocialPublishingSetting.save(%{webhook_secret: "test-webhook-secret"})
    :ok
  end

  test "accepts a valid signature and deduplicates event delivery", %{conn: conn} do
    body = Jason.encode!(%{"event" => "post.published", "eventId" => "evt_test_1"})
    signature = signature(body)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-zernio-signature", signature)
      |> post("/api/webhooks/zernio", body)

    assert response(conn, 204) == ""
    assert Repo.aggregate(WebhookReceipt, :count) == 1

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-zernio-signature", signature)
      |> post("/api/webhooks/zernio", body)

    assert response(conn, 204) == ""
    assert Repo.aggregate(WebhookReceipt, :count) == 1
  end

  test "rejects an invalid signature", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-zernio-signature", "invalid")
      |> post("/api/webhooks/zernio", Jason.encode!(%{"event" => "post.failed"}))

    assert response(conn, 401) == "invalid signature"
    assert Repo.aggregate(WebhookReceipt, :count) == 0
  end

  defp signature(body) do
    :crypto.mac(:hmac, :sha256, "test-webhook-secret", body)
    |> Base.encode16(case: :lower)
  end
end
