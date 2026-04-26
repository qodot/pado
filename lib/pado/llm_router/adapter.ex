defmodule Pado.LLMRouter.Adapter do
  alias Pado.LLMRouter.{Context, Model}

  @type event_stream :: Enumerable.t()

  @type opts :: keyword

  @callback stream(Model.t(), Context.t(), opts) ::
              {:ok, event_stream} | {:error, term}

  @callback supports?(Model.t()) :: boolean
end
