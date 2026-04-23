defmodule LLMRouter.OAuth.Provider do
  @moduledoc """
  Behaviour for OAuth-based LLM providers.

  Models pi-ai's `OAuthProviderInterface` in Elixir terms. An implementation
  is a stateless module that:

    * builds an authorization URL and accepts an authorization code,
    * exchanges the code for credentials,
    * refreshes expired credentials,
    * derives the string API key used for HTTP Authorization headers.

  The caller is responsible for credential storage, scheduling refreshes,
  and routing user interaction (browser, terminal, web UI, …) through the
  `t:callbacks/0` passed to `c:login/2`.

  ## Design notes

  * The behaviour does **not** prescribe where credentials live. `c:login/2`
    returns a `LLMRouter.OAuth.Credentials.t/0` and nothing else.
  * Providers that use a `localhost` redirect URI (`uses_callback_server?/0 == true`)
    are expected to spin up a short-lived HTTP listener internally, using
    `LLMRouter.OAuth.CallbackServer` or equivalent. This is a consequence of
    the OAuth flow, not a policy choice.
  """

  alias LLMRouter.OAuth.Credentials

  @typedoc """
  Information forwarded to the user at the start of a login flow.

  * `:url` — authorize URL that must be opened in a browser.
  * `:instructions` — optional human-readable hint (e.g. "a browser window
    should open").
  """
  @type auth_info :: %{
          required(:url) => String.t(),
          optional(:instructions) => String.t()
        }

  @typedoc "Structured prompt for manual input fallback."
  @type prompt :: %{
          required(:message) => String.t(),
          optional(:placeholder) => String.t(),
          optional(:allow_empty) => boolean()
        }

  @typedoc """
  Interaction callbacks that the provider invokes during `c:login/2`.

  All callbacks are optional except `:on_auth`, which the provider calls
  exactly once with the authorize URL.

    * `:on_auth` — required. Receives the URL/instructions so the caller
      can open a browser, show UI, etc.
    * `:on_prompt` — asks the user for free-form input (e.g. a pasted
      redirect URL). Returning `{:error, reason}` aborts the login.
    * `:on_progress` — optional progress messages.
    * `:on_manual_code_input` — optional. If provided, the provider races
      this promise-like function against the callback server. Whichever
      returns first wins. Useful when the callback server cannot bind
      (port in use, firewall) and the user needs to paste manually.
  """
  @type callbacks :: %{
          required(:on_auth) => (auth_info -> any),
          optional(:on_prompt) => (prompt -> {:ok, String.t()} | {:error, term}),
          optional(:on_progress) => (String.t() -> any),
          optional(:on_manual_code_input) => (-> {:ok, String.t()} | {:error, term})
        }

  @typedoc "Stable identifier used in CLI and storage keys."
  @type id :: atom

  @doc "Stable identifier (e.g. `:openai_codex`)."
  @callback id() :: id

  @doc "Human-readable name."
  @callback name() :: String.t()

  @doc """
  Whether the provider requires a local callback server at a fixed
  `localhost` redirect URI.
  """
  @callback uses_callback_server?() :: boolean

  @doc """
  Runs the OAuth login flow and returns fresh credentials.

  Options are provider-specific, but commonly include:

    * `:originator` — OAuth `originator` parameter (client identifier).
    * `:timeout` — milliseconds to wait for the authorization code.
    * `:port`, `:host` — callback server binding (for testing).
  """
  @callback login(callbacks, keyword) :: {:ok, Credentials.t()} | {:error, term}

  @doc """
  Refreshes a credential set.

  Implementations MUST return the full, updated credentials even when the
  provider rotates the refresh token. Callers are responsible for
  persisting the returned value.
  """
  @callback refresh(Credentials.t()) :: {:ok, Credentials.t()} | {:error, term}

  @doc """
  Returns the bearer token (or equivalent) derived from credentials.

  For most providers this is `credentials.access`, but some may transform
  it (e.g. prefixing, decoding).
  """
  @callback api_key(Credentials.t()) :: String.t()

  @optional_callbacks [uses_callback_server?: 0]
end
