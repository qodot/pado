defmodule Pado.LLM.Credential.ApiKey.ZAI do
  alias Pado.LLM.Credential.OAuth.Credentials

  @behaviour Pado.LLM.Credential.OAuth.Provider

  @ten_years 10 * 365 * 24 * 60 * 60

  @impl true
  def id, do: :z_ai

  @impl true
  def name, do: "Z.AI API Key"

  @impl true
  def uses_callback_server?, do: false

  @impl true
  def login(callbacks, _opts) do
    prompt = %{
      message: "Enter your Z.AI API key:",
      placeholder: "ZAI_API_KEY"
    }

    with {:ok, api_key} <- callbacks.on_prompt.(prompt) do
      {:ok, Credentials.build(:z_ai, api_key, "", @ten_years)}
    end
  end

  @impl true
  def refresh(%Credentials{provider: :z_ai} = creds), do: {:ok, creds}

  def refresh(%Credentials{provider: other}),
    do: {:error, {:wrong_provider, other}}

  @impl true
  def api_key(%Credentials{provider: :z_ai, access: access}), do: access
end
