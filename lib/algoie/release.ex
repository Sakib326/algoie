defmodule Algoie.Release do
  @moduledoc "Tasks intended to be invoked from a production OTP release."

  def migrate do
    Algoie.Migrations.migrate_all()
  end
end
