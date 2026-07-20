defmodule AlgoieWeb.PublicURL do
  @moduledoc "Builds all external application URLs from the canonical APP_URL origin."

  def apex(path \\ "/") do
    base_uri()
    |> with_path(path)
    |> URI.to_string()
  end

  def tenant(workspace, section \\ :dashboard) do
    apex("/tenant/#{workspace}/#{section}")
  end

  def store(store_slug, path \\ "/") do
    uri = base_uri()

    uri
    |> Map.put(:host, "#{store_slug}.#{uri.host}")
    |> with_path(path)
    |> URI.to_string()
  end

  def origin, do: apex("")
  def host, do: base_uri().host

  defp base_uri do
    :algoie
    |> Application.get_env(:app_url, "http://localhost:4000")
    |> URI.parse()
    |> Map.put(:path, nil)
    |> Map.put(:query, nil)
    |> Map.put(:fragment, nil)
  end

  defp with_path(uri, path) do
    path = if String.starts_with?(path, "/"), do: path, else: "/#{path}"
    %{uri | path: path, query: nil, fragment: nil}
  end
end
