defmodule AlgoieWeb.ZernioWebhookController do
  use AlgoieWeb, :controller

  alias Algoie.SocialPublishing.{AccountRegistry, SocialAccount, WebhookReceipt}
  alias Algoie.SocialPublishingSetting

  require Ash.Query

  def receive(conn, payload) do
    raw_body = conn.assigns[:raw_body] || Jason.encode!(payload)
    signature = get_req_header(conn, "x-zernio-signature") |> List.first()
    secret = SocialPublishingSetting.get() |> SocialPublishingSetting.webhook_secret()

    cond do
      secret in [nil, ""] ->
        send_resp(conn, 503, "webhook not configured")

      not valid_signature?(signature, raw_body, secret) ->
        send_resp(conn, 401, "invalid signature")

      true ->
        process(conn, payload, raw_body)
    end
  end

  defp process(conn, payload, raw_body) do
    event = payload["event"] || payload["type"] || "unknown"

    event_id =
      payload["eventId"] || payload["id"] ||
        Base.encode16(:crypto.hash(:sha256, raw_body), case: :lower)

    account_id = provider_account_id(payload)

    case WebhookReceipt.insert_once(%{
           event_id: event_id,
           event: event,
           provider_account_id: account_id
         }) do
      :duplicate ->
        send_resp(conn, 204, "")

      :new ->
        route_event(event, account_id, payload)
        send_resp(conn, 204, "")
    end
  end

  defp route_event(event, account_id, payload) do
    if event in ["account.disconnected", "account.reconnected", "account.connected"] do
      update_account_status(event, account_id)
    end

    if is_binary(account_id) do
      Phoenix.PubSub.broadcast(Algoie.PubSub, "zernio:#{account_id}", {:zernio_event, payload})
    end
  end

  defp update_account_status(_event, nil), do: :ok

  defp update_account_status(event, account_id) do
    with %{tenant: tenant, local_account_id: local_id} <- AccountRegistry.get(account_id),
         {:ok, account} <- Ash.get(SocialAccount, local_id, tenant: tenant, actor: :system) do
      status = if event == "account.disconnected", do: :needs_reauth, else: :connected
      Ash.update(account, %{status: status}, tenant: tenant, actor: :system)
    end
  end

  defp provider_account_id(payload) do
    candidates = [
      payload["accountId"],
      get_in(payload, ["account", "accountId"]),
      get_in(payload, ["account", "_id"]),
      get_in(payload, ["data", "accountId"]),
      get_in(payload, ["data", "account", "accountId"]),
      get_in(payload, ["data", "account", "_id"]),
      get_in(payload, ["post", "platforms", Access.at(0), "accountId"])
    ]

    Enum.find(candidates, &is_binary/1)
  end

  defp valid_signature?(nil, _body, _secret), do: false

  defp valid_signature?(signature, body, secret) do
    supplied = String.replace_prefix(signature, "sha256=", "") |> String.downcase()
    expected = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
    byte_size(supplied) == byte_size(expected) and Plug.Crypto.secure_compare(supplied, expected)
  end
end
