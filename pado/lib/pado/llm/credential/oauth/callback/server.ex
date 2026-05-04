defmodule Pado.LLM.Credential.OAuth.Callback.Server do
  @default_port 1455
  @default_host {127, 0, 0, 1}
  @default_timeout 300_000

  @type handle :: %{
          pid: pid,
          ref: reference,
          expected_state: String.t()
        }

  def start(expected_state, opts \\ []) when is_binary(expected_state) do
    ensure_deps!()

    port = Keyword.get(opts, :port, @default_port)
    host = Keyword.get(opts, :host, @default_host)

    parent = self()
    ref = make_ref()

    plug_opts = %{parent: parent, ref: ref, expected_state: expected_state}

    bandit_opts = [
      plug: {Pado.LLM.Credential.OAuth.Callback.Server.Plug, plug_opts},
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

  def await_code(%{ref: ref}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    receive do
      {^ref, result} -> result
    after
      timeout -> {:error, :timeout}
    end
  end

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

  defp ensure_deps! do
    cond do
      not Code.ensure_loaded?(Bandit) ->
        raise """
        Pado.LLM.Credential.OAuth.Callback.Server requires :bandit.

        Add the following to your mix.exs deps:

            {:bandit, "~> 1.5"},
            {:plug, "~> 1.16"}
        """

      not Code.ensure_loaded?(Plug) ->
        raise """
        Pado.LLM.Credential.OAuth.Callback.Server requires :plug.

        Add the following to your mix.exs deps:

            {:plug, "~> 1.16"}
        """

      not Code.ensure_loaded?(Pado.LLM.Credential.OAuth.Callback.Server.Plug) ->
        raise """
        Pado.LLM.Credential.OAuth.Callback.Server.Plug was not compiled.
        :plug was likely missing at compile time. Re-fetch dependencies
        and recompile.
        """

      true ->
        :ok
    end
  end
end

if Code.ensure_loaded?(Plug) do
  defmodule Pado.LLM.Credential.OAuth.Callback.Server.Plug do
    @behaviour Plug

    import Plug.Conn
    alias Pado.LLM.Credential.OAuth.Callback.Page

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
          |> send_resp(400, Page.error_html("State value did not match."))

        is_nil(code) or code == "" ->
          send(parent, {ref, {:error, :missing_code}})

          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> send_resp(400, Page.error_html("Authorization code was not provided."))

        true ->
          send(parent, {ref, {:ok, code}})

          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> send_resp(200, Page.success_html())
      end
    end

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/html; charset=utf-8")
      |> send_resp(404, Page.error_html("Callback path not found."))
    end
  end
end
