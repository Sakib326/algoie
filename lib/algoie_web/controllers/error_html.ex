defmodule AlgoieWeb.ErrorHTML do
  @moduledoc """
  Custom error pages for the application.
  """
  use AlgoieWeb, :html

  embed_templates "error_html/*"
end
