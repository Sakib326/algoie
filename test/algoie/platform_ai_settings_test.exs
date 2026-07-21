defmodule Algoie.PlatformAISettingsTest do
  use ExUnit.Case, async: true

  alias Algoie.PlatformAISettings

  test "requires an allowed default model and API key before enabling" do
    changeset =
      PlatformAISettings.changeset(%PlatformAISettings{}, %{
        enabled: true,
        default_model: "openai/gpt-5",
        allowed_models_text: "openai/gpt-5"
      })

    refute changeset.valid?
    assert {"is required while AI is enabled", _} = changeset.errors[:openrouter_api_key]
  end

  test "normalizes the SaaS-admin model allow-list" do
    changeset =
      PlatformAISettings.changeset(%PlatformAISettings{}, %{
        enabled: true,
        openrouter_api_key: "secret",
        default_model: "openai/gpt-5",
        allowed_models_text: " openai/gpt-5 \nopenai/gpt-5\nopenai/gpt-5-mini "
      })

    assert changeset.valid?

    assert Ecto.Changeset.get_change(changeset, :allowed_models) == [
             "openai/gpt-5",
             "openai/gpt-5-mini"
           ]

    assert PlatformAISettings.allowed_model?(
             Ecto.Changeset.apply_changes(changeset),
             "openai/gpt-5"
           )
  end
end
