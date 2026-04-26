defmodule Pado.LLMRouter.Provider do
  alias Pado.LLMRouter.{Context, Model}
  alias Pado.LLMRouter.OAuth.Credentials

  @callback stream(Model.t(), Context.t(), Credentials.t(), String.t(), keyword) ::
              {:ok, Enumerable.t()} | {:error, term}
end
