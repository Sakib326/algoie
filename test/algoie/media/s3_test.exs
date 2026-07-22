defmodule Algoie.Media.S3Test do
  use ExUnit.Case, async: true

  alias Algoie.Media.S3
  alias Algoie.PlatformStorageSettings

  test "builds and recovers path-style object URLs" do
    settings = %PlatformStorageSettings{
      backend: "s3",
      endpoint: "https://objects.example.com",
      bucket: "media",
      public_base_url: "https://cdn.example.com",
      path_style: true
    }

    assert S3.public_url(settings, "tenant-id/photo one.jpg") ==
             "https://cdn.example.com/tenant-id/photo%20one.jpg"

    assert S3.object_key(settings, "https://cdn.example.com/tenant-id/photo%20one.jpg") ==
             "tenant-id/photo one.jpg"
  end

  test "builds virtual-hosted URLs when path style is disabled" do
    settings = %PlatformStorageSettings{
      backend: "s3",
      endpoint: "https://s3.example.com",
      bucket: "media",
      public_base_url: "https://media.s3.example.com",
      path_style: false
    }

    assert S3.public_url(settings, "tenant/file.jpg") ==
             "https://media.s3.example.com/tenant/file.jpg"
  end

  test "uses the authenticated application proxy for a private bucket" do
    settings = %PlatformStorageSettings{
      backend: "s3",
      endpoint: "https://objects.example.com",
      bucket: "media",
      path_style: true
    }

    assert S3.public_url(settings, "tenant_id/file.jpg") == "/media/s3/tenant_id/file.jpg"
    assert S3.object_key(settings, "/media/s3/tenant_id/file.jpg") == "tenant_id/file.jpg"
  end
end
