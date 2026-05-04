defmodule Pado.LLM.Credential.OAuth.Provider do
  alias Pado.LLM.Credential.OAuth.Credentials

  @type auth_info :: %{
          required(:url) => String.t(),
          optional(:instructions) => String.t()
        }

  @type prompt :: %{
          required(:message) => String.t(),
          optional(:placeholder) => String.t(),
          optional(:allow_empty) => boolean()
        }

  @type callbacks :: %{
          required(:on_auth) => (auth_info -> any),
          optional(:on_prompt) => (prompt -> {:ok, String.t()} | {:error, term}),
          optional(:on_progress) => (String.t() -> any),
          optional(:on_manual_code_input) => (-> {:ok, String.t()} | {:error, term})
        }

  @type id :: atom

  @callback id() :: id

  @callback name() :: String.t()

  @callback uses_callback_server?() :: boolean

  @callback login(callbacks, keyword) :: {:ok, Credentials.t()} | {:error, term}

  @callback refresh(Credentials.t()) :: {:ok, Credentials.t()} | {:error, term}

  @callback api_key(Credentials.t()) :: String.t()

  @optional_callbacks [uses_callback_server?: 0]
end
