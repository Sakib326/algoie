defmodule Algoie.EmailRuntimeTest do
  use ExUnit.Case, async: true

  test "does not require SMTP modules for other adapters" do
    refute_loader = fn _module -> false end

    assert :ok =
             Algoie.EmailRuntime.validate(
               [adapter: Swoosh.Adapters.Test],
               refute_loader
             )
  end

  test "returns a controlled error when the SMTP runtime is unavailable" do
    refute_loader = fn _module -> false end

    assert {:error, {:smtp_runtime_unavailable, [:mimemail, :gen_smtp_client]}} =
             Algoie.EmailRuntime.validate(
               [adapter: Swoosh.Adapters.SMTP],
               refute_loader
             )
  end

  test "accepts SMTP when its runtime modules can be loaded" do
    assert :ok = Algoie.EmailRuntime.validate(adapter: Swoosh.Adapters.SMTP)
  end

  test "uses the SMTP relay hostname for TLS server-name indication" do
    assert [server_name_indication: ~c"sandbox.smtp.mailtrap.io"] =
             Algoie.EmailRuntime.smtp_tls_options("sandbox.smtp.mailtrap.io")
  end
end
