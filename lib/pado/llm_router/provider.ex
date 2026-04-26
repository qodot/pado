defmodule Pado.LLMRouter.Provider do
  alias Pado.LLMRouter.{Context, Model, Stream}
  alias Pado.LLMRouter.OAuth.Credentials

  @callback stream(Model.t(), Context.t(), Credentials.t(), String.t(), keyword) ::
              {:ok, Stream.t()} | {:error, term}
end
