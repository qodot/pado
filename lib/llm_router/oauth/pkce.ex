defmodule LLMRouter.OAuth.PKCE do
  @moduledoc """
  PKCE (Proof Key for Code Exchange) helpers per RFC 7636.

  Mirrors pi-ai's `utils/oauth/pkce.ts`:

    * `verifier` is 32 random bytes, base64url-encoded (no padding).
    * `challenge` is `SHA256(verifier)`, base64url-encoded (no padding).
    * `code_challenge_method` is always `"S256"`.
  """

  @verifier_bytes 32

  @typedoc "PKCE pair used in an authorization request."
  @type pair :: %{verifier: String.t(), challenge: String.t()}

  @doc "Generates a fresh verifier/challenge pair."
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
  Generates an opaque random `state` parameter of the given byte length
  (default 16), encoded as lowercase hex — matches Pi's `createState`.
  """
  @spec state(pos_integer) :: String.t()
  def state(bytes \\ 16) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
