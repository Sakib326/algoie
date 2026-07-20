defmodule Algoie.EmailRuntime do
  @moduledoc false

  @smtp_modules [:mimemail, :gen_smtp_client]

  def validate(mailer_config, loader \\ &Code.ensure_loaded?/1) do
    if Keyword.get(mailer_config, :adapter) == Swoosh.Adapters.SMTP do
      case Enum.reject(@smtp_modules, loader) do
        [] -> :ok
        missing -> {:error, {:smtp_runtime_unavailable, missing}}
      end
    else
      :ok
    end
  end

  def smtp_tls_options(host) when is_binary(host) and host != "" do
    [server_name_indication: String.to_charlist(host)]
  end

  def smtp_tls_options(_host), do: []
end
