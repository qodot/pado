defmodule LLMRouter.OAuth.PKCE do
  @moduledoc """
  RFC 7636 기반의 PKCE(Proof Key for Code Exchange) 헬퍼.

  pi-ai의 `utils/oauth/pkce.ts`와 동일한 규약을 따른다.

    * `verifier`는 랜덤 32바이트를 base64url(패딩 없음)로 인코딩한 값.
    * `challenge`는 `SHA256(verifier)`를 base64url(패딩 없음)로 인코딩한 값.
    * `code_challenge_method`는 항상 `"S256"`.
  """

  @verifier_bytes 32

  @typedoc "인가 요청에 사용되는 PKCE 쌍."
  @type pair :: %{verifier: String.t(), challenge: String.t()}

  @doc "새로운 verifier/challenge 쌍을 생성한다."
  @spec generate() :: pair
  def generate do
    verifier =
      @verifier_bytes
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    challenge =
      :sha256
      |> :crypto.hash(verifier)
      |> Base.url_encode64(padding: false)

    %{verifier: verifier, challenge: challenge}
  end

  @doc """
  지정된 바이트 수(기본 16)만큼의 랜덤 `state` 파라미터를 생성한다.
  소문자 16진수로 인코딩된다. Pi의 `createState`와 같은 형식이다.
  """
  @spec state(pos_integer) :: String.t()
  def state(bytes \\ 16) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
