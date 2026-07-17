defmodule Algoie.Media.Storage do
  @moduledoc """
  Local-disk storage backend for uploaded media.

  Files are written to `priv/static/uploads/<tenant>/<random>-<filename>` and
  served back at the public path `/uploads/<tenant>/<random>-<filename>` via
  `Plug.Static` (see `AlgoieWeb.static_paths/0`).

  Kept as a single small module so swapping to an object store (S3, GCS, ...)
  later only requires changing `put/3` and `delete/1`.
  """

  @max_file_size 10_000_000
  @accepted_extensions ~w(.jpg .jpeg .png .gif .webp .svg)

  def max_file_size, do: @max_file_size
  def accepted_extensions, do: @accepted_extensions

  @doc """
  Copies a temporary upload file into permanent storage for `tenant` and
  returns `{:ok, %{url:, filename:, size:}}`.
  """
  def put(tenant, source_path, original_filename) do
    ext = original_filename |> Path.extname() |> String.downcase()
    safe_name = slugify_filename(original_filename)
    filename = "#{Ecto.UUID.generate()}-#{safe_name}"

    dest_dir = upload_dir(tenant)
    File.mkdir_p!(dest_dir)

    dest_path = Path.join(dest_dir, filename)

    with :ok <- File.cp(source_path, dest_path),
         {:ok, %File.Stat{size: size}} <- File.stat(dest_path) do
      {:ok,
       %{
         url: "/uploads/#{tenant}/#{filename}",
         filename: original_filename,
         extension: ext,
         size: size
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes the file backing a stored asset `url` (best-effort, ignores
  missing files).
  """
  def delete(nil), do: :ok

  def delete(url) do
    case public_path_for(url) do
      nil -> :ok
      path -> File.rm(path)
    end

    :ok
  end

  defp public_path_for("/uploads/" <> _rest = url) do
    Path.join([Application.app_dir(:algoie, "priv/static"), url])
  end

  defp public_path_for(_), do: nil

  defp upload_dir(tenant) do
    Path.join([Application.app_dir(:algoie, "priv/static"), "uploads", tenant])
  end

  defp slugify_filename(name) do
    base = name |> Path.basename() |> Path.rootname()
    ext = name |> Path.extname() |> String.downcase()

    slug =
      base
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    slug = if slug == "", do: "file", else: slug
    slug <> ext
  end
end
