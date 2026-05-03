defmodule Pado.LLMRouter.Credential.OAuth.OpenAICodexTest do
  use ExUnit.Case, async: true

  alias Pado.LLMRouter.Credential.OAuth.OpenAICodex

  test "수동 인가 입력에서 코드와 state를 파싱한다" do
    assert OpenAICodex.parse_authorization_input("") == %{}
    assert OpenAICodex.parse_authorization_input("code_dummy") == %{code: "code_dummy"}

    assert OpenAICodex.parse_authorization_input("code_dummy#state_dummy") == %{
             code: "code_dummy",
             state: "state_dummy"
           }

    assert OpenAICodex.parse_authorization_input("code=code_dummy&state=state_dummy") == %{
             code: "code_dummy",
             state: "state_dummy"
           }

    assert OpenAICodex.parse_authorization_input(
             "http://localhost:1455/auth/callback?code=code_dummy&state=state_dummy"
           ) == %{code: "code_dummy", state: "state_dummy"}
  end

  test "Codex access JWT에서 account_id를 추출한다" do
    token =
      dummy_jwt(%{
        "https://api.openai.com/auth" => %{
          "chatgpt_account_id" => "acct_dummy"
        }
      })

    assert OpenAICodex.parse_account_id(token) == {:ok, "acct_dummy"}
  end

  test "account_id가 없는 JWT는 오류를 반환한다" do
    assert OpenAICodex.parse_account_id(dummy_jwt(%{})) == {:error, :missing_account_id}
    assert OpenAICodex.parse_account_id("not-a-jwt") == {:error, :missing_account_id}
  end

  defp dummy_jwt(payload) do
    header = %{"alg" => "none", "typ" => "JWT"}

    [header, payload, "signature"]
    |> Enum.map(fn part ->
      part
      |> encode_json_part()
      |> Base.url_encode64(padding: false)
    end)
    |> Enum.join(".")
  end

  defp encode_json_part(part) when is_map(part), do: Jason.encode!(part)
  defp encode_json_part(part) when is_binary(part), do: part
end
