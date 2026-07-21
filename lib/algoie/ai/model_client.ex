defmodule Algoie.AI.ModelClient do
  @moduledoc "Provider-neutral model client contract."

  @callback chat([map()], keyword()) :: {:ok, map()} | {:error, term()}
end
