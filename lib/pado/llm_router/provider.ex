defmodule Pado.LLMRouter.Provider do
  alias Pado.LLMRouter.{Context, Model}

  @callback stream(Model.t(), Context.t(), keyword) ::
              {:ok, Enumerable.t()} | {:error, term}
end
