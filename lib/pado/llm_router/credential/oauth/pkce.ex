defmodule Pado.LLMRouter.Credential.OAuth.PKCE do
  @verifier_bytes 32

  @type pair :: %{verifier: String.t(), challenge: String.t()}

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

  def state(bytes \\ 16) when is_integer(bytes) and bytes > 0 do
    bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end
end
