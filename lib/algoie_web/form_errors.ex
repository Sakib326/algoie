defmodule AlgoieWeb.FormErrors do
  @moduledoc false

  @doc "Converts field-aware Ash errors into the format expected by Phoenix forms."
  def to_keyword(error) do
    error
    |> Ash.Error.to_error_class()
    |> Map.get(:errors, [])
    |> Enum.flat_map(&field_errors/1)
    |> Enum.uniq()
  end

  defp field_errors(error) do
    fields =
      case Map.get(error, :fields) do
        fields when is_list(fields) and fields != [] -> fields
        _ -> List.wrap(Map.get(error, :field))
      end

    message = Map.get(error, :message) || Exception.message(error)
    vars = Map.get(error, :vars) || []

    for field <- fields, is_atom(field), do: {field, {message, vars}}
  end
end
