defmodule Algoie.Accounts.EmailOtpTest do
  use Algoie.DataCase, async: true

  alias Algoie.Accounts.EmailOtp

  test "codes are single-use and scoped by purpose and context" do
    email = "otp-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, code} = EmailOtp.issue(email, :registration, "tenant-a")
    assert {:error, :invalid_code} = EmailOtp.verify(email, :password_reset, "tenant-a", code)
    assert {:error, :invalid_code} = EmailOtp.verify(email, :registration, "tenant-b", code)
    assert :ok = EmailOtp.verify(email, :registration, "tenant-a", code)
    assert {:error, :invalid_code} = EmailOtp.verify(email, :registration, "tenant-a", code)
  end

  test "incorrect attempts do not expose or consume a valid code immediately" do
    email = "attempt-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, code} = EmailOtp.issue(email, :password_reset)
    assert {:error, :invalid_code} = EmailOtp.verify(email, :password_reset, "platform", "000000")
    assert :ok = EmailOtp.verify(email, :password_reset, "platform", code)
  end

  test "issuance is rate limited" do
    email = "rate-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, _code} = EmailOtp.issue(email, :registration)
    assert {:error, :rate_limited} = EmailOtp.issue(email, :registration)
  end
end
