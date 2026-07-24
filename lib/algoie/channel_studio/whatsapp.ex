defmodule Algoie.ChannelStudio.WhatsApp do
  @moduledoc "WhatsApp Business messaging operations."

  alias Algoie.ChannelStudio

  def number_info(account_id),
    do: ChannelStudio.get("/whatsapp/number-info", accountId: account_id)

  def templates(account_id), do: ChannelStudio.get("/whatsapp/templates", accountId: account_id)

  def template(account_id, name) do
    ChannelStudio.get("/whatsapp/templates/#{ChannelStudio.segment(name)}", accountId: account_id)
  end

  def create_template(payload), do: ChannelStudio.mutate(:post, "/whatsapp/templates", payload)
  def broadcasts(params), do: ChannelStudio.get("/broadcasts", params)
  def broadcast(id), do: ChannelStudio.get("/broadcasts/#{ChannelStudio.segment(id)}")
  def create_broadcast(payload), do: ChannelStudio.mutate(:post, "/broadcasts", payload)

  def add_recipients(id, phones) do
    ChannelStudio.mutate(:post, "/broadcasts/#{ChannelStudio.segment(id)}/recipients", %{
      "phones" => phones
    })
  end

  def send_broadcast(id) do
    ChannelStudio.mutate(:post, "/broadcasts/#{ChannelStudio.segment(id)}/send")
  end

  def flows(account_id), do: ChannelStudio.get("/whatsapp/flows", accountId: account_id)
  def create_flow(payload), do: ChannelStudio.mutate(:post, "/whatsapp/flows", payload)

  def profile(account_id),
    do: ChannelStudio.get("/whatsapp/business-profile", accountId: account_id)

  def update_profile(payload) do
    ChannelStudio.mutate(:post, "/whatsapp/business-profile", payload)
  end

  def conversions(account_id),
    do: ChannelStudio.get("/whatsapp/conversions", accountId: account_id)

  def send_conversion(payload) do
    ChannelStudio.mutate(:post, "/whatsapp/conversions", payload)
  end
end
