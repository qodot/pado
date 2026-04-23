defmodule LLMRouter.OAuth.CallbackServer do
  @moduledoc """
  One-shot HTTP listener for OAuth authorization callbacks.

  Binds `http://127.0.0.1:1455/auth/callback` (the redirect URI registered
  for the shared public OAuth clients used by `LLMRouter.OAuth.OpenAICodex`
  and peers) and forwards the received authorization code back to the
  calling process as a message.

  Mirrors pi-ai's `startLocalOAuthServer` (utils/oauth/openai-codex.ts).
  The server exists for exactly one login flow: once a code is received
  (or a validation error triggers), the caller is expected to invoke
  `stop/1` to tear everything down.

  ## Optional dependencies

  `:bandit` and `:plug` are declared as **optional** dependencies of
  `:llm_router`. They are only required when a login flow is actually
  initiated (either through `mix llm_router.login` or by calling
  `c:LLMRouter.OAuth.Provider.login/2`). Consumers that already hold
  credentials (e.g. a server app reading from Vault) do not need them.

  If the deps are missing, `start/2` raises a descriptive error with
  instructions for how to add them.

  ## Usage

      state = LLMRouter.OAuth.PKCE.state()
      {:ok, server} = LLMRouter.OAuth.CallbackServer.start(state)
      # … direct the user's browser at the authorize URL …
      case LLMRouter.OAuth.CallbackServer.await_code(server, timeout: 120_000) do
        {:ok, code} -> # exchange code
        {:error, :timeout} -> # user did not complete
        {:error, reason} -> # state mismatch, missing code, …
      end
      LLMRouter.OAuth.CallbackServer.stop(server)

  ## Messages

  While alive, the server sends exactly one message to the calling
  process:

      {ref, {:ok, code}}            # happy path
      {ref, {:error, :state_mismatch}}
      {ref, {:error, :missing_code}}

  `await_code/2` encapsulates this receive; direct inspection is only
  needed for advanced use cases (e.g. racing with a manual-paste prompt).
  """

  @default_port 1455
  @default_host {127, 0, 0, 1}
  @default_timeout 300_000

  @typedoc "Opaque handle returned by `start/2`."
  @type handle :: %{
          pid: pid,
          ref: reference,
          expected_state: String.t()
        }

  @doc """
  Starts the listener and returns a handle.

  Options:

    * `:port` — TCP port to bind (default `1455`; overriding this will
      break real OAuth flows since the provider's redirect URI is
      registered against 1455 — reserved for tests).
    * `:host` — IP tuple to bind (default `{127, 0, 0, 1}`).
  """
  @spec start(String.t(), keyword) :: {:ok, handle} | {:error, term}
  def start(expected_state, opts \\ []) when is_binary(expected_state) do
    ensure_deps!()

    port = Keyword.get(opts, :port, @default_port)
    host = Keyword.get(opts, :host, @default_host)

    parent = self()
    ref = make_ref()

    plug_opts = %{parent: parent, ref: ref, expected_state: expected_state}

    bandit_opts = [
      plug: {LLMRouter.OAuth.CallbackServer.Plug, plug_opts},
      port: port,
      ip: host,
      startup_log: false
    ]

    case apply(Bandit, :start_link, [bandit_opts]) do
      {:ok, pid} ->
        {:ok, %{pid: pid, ref: ref, expected_state: expected_state}}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Blocks until the callback handler sends a result, or the timeout
  elapses.

  Options:

    * `:timeout` — milliseconds (default `300_000`, i.e. 5 minutes).
  """
  @spec await_code(handle, keyword) ::
          {:ok, String.t()} | {:error, :timeout | :state_mismatch | :missing_code | term}
  def await_code(%{ref: ref}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    receive do
      {^ref, result} -> result
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Shuts down the listener. Safe to call multiple times.
  """
  @spec stop(handle) :: :ok
  def stop(%{pid: pid}) do
    try do
      _ = apply(ThousandIsland, :stop, [pid])
      :ok
    catch
      _, _ ->
        try do
          Process.exit(pid, :shutdown)
          :ok
        catch
          _, _ -> :ok
        end
    end
  end

  # --- private ---

  defp ensure_deps! do
    cond do
      not Code.ensure_loaded?(Bandit) ->
        raise """
        LLMRouter.OAuth.CallbackServer requires :bandit.

        Add to your mix.exs:

            {:bandit, "~> 1.5"},
            {:plug, "~> 1.16"}
        """

      not Code.ensure_loaded?(Plug) ->
        raise """
        LLMRouter.OAuth.CallbackServer requires :plug.

        Add to your mix.exs:

            {:plug, "~> 1.16"}
        """

      not Code.ensure_loaded?(LLMRouter.OAuth.CallbackServer.Plug) ->
        # Defensive: the plug module only compiles when :plug is available.
        raise """
        LLMRouter.OAuth.CallbackServer.Plug was not compiled. This usually
        means :plug was missing at compile time. Re-fetch deps and recompile.
        """

      true ->
        :ok
    end
  end
end

# The Plug implementation only compiles when :plug is available, so the
# library is still usable (for non-login operations such as refresh) even
# when consumers omit the optional deps.
if Code.ensure_loaded?(Plug) do
  defmodule LLMRouter.OAuth.CallbackServer.Plug do
    @moduledoc false
    @behaviour Plug

    import Plug.Conn
    alias LLMRouter.OAuth.OAuthPage

    @impl Plug
    def init(opts), do: opts

    @impl Plug
    def call(%Plug.Conn{request_path: "/auth/callback"} = conn, %{
          parent: parent,
          ref: ref,
          expected_state: expected
        }) do
      conn = fetch_query_params(conn)
      got_state = conn.query_params["state"]
      code = conn.query_params["code"]

      cond do
        got_state != expected ->
          send(parent, {ref, {:error, :state_mismatch}})

          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> send_resp(400, OAuthPage.error_html("State mismatch."))

        is_nil(code) or code == "" ->
          send(parent, {ref, {:error, :missing_code}})

          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> send_resp(400, OAuthPage.error_html("Missing authorization code."))

        true ->
          send(parent, {ref, {:ok, code}})

          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> send_resp(200, OAuthPage.success_html())
      end
    end

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/html; charset=utf-8")
      |> send_resp(404, OAuthPage.error_html("Callback route not found."))
    end
  end
end
