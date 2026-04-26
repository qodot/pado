defmodule Pado.LLMRouter do
  alias Pado.LLMRouter.{Context, Model}

  @provider_map %{
    openai_codex: Pado.LLMRouter.Providers.OpenAICodex
  }

  def stream(%Model{provider: provider} = model, %Context{} = ctx, opts \\ []) do
    case Map.fetch(@provider_map, provider) do
      {:ok, adapter} -> adapter.stream(model, ctx, opts)
      :error -> {:error, {:unsupported_provider, provider}}
    end
  end
end
