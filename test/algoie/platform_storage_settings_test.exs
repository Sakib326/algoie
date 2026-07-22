defmodule Algoie.PlatformStorageSettingsTest do
  use ExUnit.Case, async: true

  alias Algoie.PlatformStorageSettings

  test "local storage is valid without remote credentials" do
    changeset = PlatformStorageSettings.changeset(%PlatformStorageSettings{}, %{backend: "local"})

    assert changeset.valid?
    assert PlatformStorageSettings.configured?(Ecto.Changeset.apply_changes(changeset))
  end

  test "S3 storage requires its endpoint, bucket, region, and credentials" do
    changeset = PlatformStorageSettings.changeset(%PlatformStorageSettings{}, %{backend: "s3"})

    refute changeset.valid?
    assert {"can't be blank", _} = changeset.errors[:endpoint]
    assert {"is required for S3 storage", _} = changeset.errors[:secret_access_key]
  end

  test "accepts and normalizes a complete S3-compatible configuration" do
    changeset =
      PlatformStorageSettings.changeset(%PlatformStorageSettings{}, %{
        backend: "s3",
        endpoint: "https://objects.example.com/",
        region: "auto",
        bucket: "algoie-media",
        access_key_id: "access-key",
        secret_access_key: "secret-key",
        public_base_url: "https://cdn.example.com/",
        path_style: true
      })

    assert changeset.valid?
    settings = Ecto.Changeset.apply_changes(changeset)
    assert settings.endpoint == "https://objects.example.com"
    assert settings.public_base_url == "https://cdn.example.com"
    assert PlatformStorageSettings.s3?(settings)
    assert PlatformStorageSettings.secret_access_key(settings) == "secret-key"
  end

  test "rejects malformed endpoints and bucket names" do
    changeset =
      PlatformStorageSettings.changeset(%PlatformStorageSettings{}, %{
        backend: "s3",
        endpoint: "objects.example.com",
        region: "auto",
        bucket: "Invalid_Bucket",
        access_key_id: "access-key",
        secret_access_key: "secret-key"
      })

    refute changeset.valid?
    assert {"must be a complete HTTP or HTTPS URL", _} = changeset.errors[:endpoint]
    assert {"must be a valid S3 bucket name", _} = changeset.errors[:bucket]
  end
end
