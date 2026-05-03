defmodule Pado.LLM.Credential.OAuth.PKCETest do
  use ExUnit.Case, async: true

  alias Pado.LLM.Credential.OAuth.PKCE

  test "PKCE verifier와 challenge는 base64url 형식이다" do
    %{verifier: verifier, challenge: challenge} = PKCE.generate()

    assert byte_size(verifier) == 43
    assert byte_size(challenge) == 43
    assert verifier =~ ~r/^[A-Za-z0-9_-]+$/
    assert challenge =~ ~r/^[A-Za-z0-9_-]+$/
    refute String.contains?(verifier, "=")
    refute String.contains?(challenge, "=")
  end

  test "state는 요청한 바이트 수의 소문자 16진수 문자열이다" do
    assert PKCE.state() =~ ~r/^[0-9a-f]{32}$/
    assert PKCE.state(8) =~ ~r/^[0-9a-f]{16}$/
  end
end
