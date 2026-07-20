defmodule AlgoieWeb.FormErrorsTest do
  use ExUnit.Case, async: true

  alias Ash.Error.Changes.InvalidChanges

  test "converts Ash validation errors into Phoenix field errors" do
    error =
      Ash.Error.Invalid.exception(
        errors: [
          InvalidChanges.exception(
            fields: [:slug],
            message: "must contain lowercase letters and hyphens only"
          )
        ]
      )

    assert AlgoieWeb.FormErrors.to_keyword(error) == [
             slug: {"must contain lowercase letters and hyphens only", []}
           ]
  end

  test "does not invent a field for global errors" do
    error =
      Ash.Error.Invalid.exception(
        errors: [InvalidChanges.exception(message: "request could not be completed")]
      )

    assert AlgoieWeb.FormErrors.to_keyword(error) == []
  end
end
