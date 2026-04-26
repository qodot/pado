defmodule Pado.LLMRouter do
  alias Pado.LLMRouter.{Context, Model}

  @provider_map %{
    openai_codex: Pado.LLMRouter.Providers.OpenAICodex
  }

  def stream(
        %Model{provider: provider} = model,
        %Context{} = ctx,
        credentials,
        session_id,
        opts \\ []
      ) do
    case Map.fetch(@provider_map, provider) do
      {:ok, provider_module} -> provider_module.stream(model, ctx, credentials, session_id, opts)
      :error -> {:error, {:unsupported_provider, provider}}
    end
  end
end
