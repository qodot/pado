defmodule Pado.LLMRouter.OAuth.CredentialsTest do
  use ExUnit.Case, async: true

  alias Pado.LLMRouter.OAuth.Credentials

  test "크레덴셜을 JSON 호환 맵으로 직렬화하고 다시 읽는다" do
    expires_at = ~U[2026-04-26 12:34:56Z]

    creds = %Credentials{
      provider: :openai_codex,
      access: "access_dummy",
      refresh: "refresh_dummy",
      expires_at: expires_at,
      extra: %{"account_id" => "acct_dummy"}
    }

    map = Credentials.to_map(creds)

    assert map == %{
             "provider" => "openai_codex",
             "access" => "access_dummy",
             "refresh" => "refresh_dummy",
             "expires_at" => "2026-04-26T12:34:56Z",
             "extra" => %{"account_id" => "acct_dummy"}
           }

    assert {:ok, ^creds} = Credentials.from_map(map)
  end

  test "Pi 호환 epoch 밀리초 expires_at을 읽는다" do
    expires_at = ~U[2026-04-26 12:34:56.789Z]
    millis = DateTime.to_unix(expires_at, :millisecond)

    assert {:ok, creds} =
             Credentials.from_map(%{
               "provider" => "openai_codex",
               "access" => "access_dummy",
               "refresh" => "refresh_dummy",
               "expires_at" => millis
             })

    assert creds.provider == :openai_codex
    assert creds.expires_at == expires_at
    assert creds.extra == %{}
  end

  test "필수 필드가 없거나 expires_at 형식이 잘못되면 오류를 반환한다" do
    assert {:error, {:missing, :refresh}} =
             Credentials.from_map(%{
               "provider" => "openai_codex",
               "access" => "access_dummy",
               "expires_at" => "2026-04-26T12:34:56Z"
             })

    assert {:error, {:invalid_expires_at, _}} =
             Credentials.from_map(%{
               "provider" => "openai_codex",
               "access" => "access_dummy",
               "refresh" => "refresh_dummy",
               "expires_at" => "not-a-date"
             })
  end

  test "만료와 선제 갱신 필요 여부를 판정한다" do
    past = %Credentials{
      provider: :openai_codex,
      access: "access_dummy",
      refresh: "refresh_dummy",
      expires_at: DateTime.add(DateTime.utc_now(), -10, :second)
    }

    future = %{past | expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)}

    assert Credentials.expired?(past)
    refute Credentials.expired?(future)

    assert Credentials.stale?(future, 7200)
    refute Credentials.stale?(future, 60)
  end
end
