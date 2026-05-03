defmodule Pado.LLM.Credential do
  alias Pado.LLM.Credential.OAuth.Credentials

  @type provider :: atom()
  @type loader_mapping :: {module(), term()}

  @spec load(provider) :: {:ok, Credentials.t()} | {:error, term()}
  def load(provider) when is_atom(provider) do
    with {:ok, {loader, arg}} <- lookup_loader(provider) do
      loader.load(arg)
    end
  end

  @spec save(provider, Credentials.t()) :: :ok | {:error, term()}
  def save(provider, %Credentials{} = creds) when is_atom(provider) do
    with {:ok, {loader, arg}} <- lookup_loader(provider) do
      loader.save(creds, arg)
    end
  end

  defp lookup_loader(provider) do
    case Map.fetch(Application.get_env(:pado, :credentials, %{}), provider) do
      {:ok, mapping} -> {:ok, mapping}
      :error -> {:error, {:unconfigured_provider, provider}}
    end
  end
end
