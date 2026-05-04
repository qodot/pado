defmodule Pado.LLM.Provider do
  alias Pado.LLM.{Context, Model, Stream}
  alias Pado.LLM.Credential.OAuth.Credentials

  @callback stream(Model.t(), Context.t(), Credentials.t(), String.t(), keyword) ::
              {:ok, Stream.t()} | {:error, term}
end
