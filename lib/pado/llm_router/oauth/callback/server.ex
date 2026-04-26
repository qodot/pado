defmodule Pado.LLMRouter.OAuth.Callback.Server do
  @moduledoc """
  OAuth 인가 콜백을 받는 일회성 HTTP 리스너.

  `Pado.LLMRouter.OAuth.OpenAICodex` 등이 사용하는 공용 public OAuth
  클라이언트의 redirect URI로 등록된 `http://127.0.0.1:1455/auth/callback`
  에 바인딩하고, 수신한 인가 코드를 호출자 프로세스에 메시지로 전달한다.

  pi-ai의 `startLocalOAuthServer`(utils/oauth/openai-codex.ts)와 같은
  역할을 한다. 서버는 정확히 한 번의 로그인 플로우 동안만 살아 있다.
  코드를 수신(또는 검증 실패로 오류를 전달)하면 호출자는 `stop/1`로
  모든 것을 정리해야 한다.

  ## 선택 의존성

  `:bandit`과 `:plug`는 `:pado`의 **선택** 의존성이다. 로그인
  플로우를 실제로 시작할 때(즉 `mix llm_router.login` 또는
  `c:Pado.LLMRouter.OAuth.Provider.login/2` 호출 시)에만 필요하다. 이미
  크레덴셜을 가지고 있는 소비자(예: Vault에서 읽는 서버 앱)는 설치할
  필요가 없다.

  의존성이 없는 상태에서 `start/2`를 호출하면 추가 안내가 담긴 에러를
  raise 한다.

  ## 사용

      state = Pado.LLMRouter.OAuth.PKCE.state()
      {:ok, server} = Pado.LLMRouter.OAuth.Callback.Server.start(state)

      case Pado.LLMRouter.OAuth.Callback.Server.await_code(server, timeout: 120_000) do
        {:ok, code} -> code
        {:error, reason} -> {:error, reason}
      end

      Pado.LLMRouter.OAuth.Callback.Server.stop(server)

  ## 메시지

  서버가 살아 있는 동안 호출자 프로세스에 정확히 한 번 메시지를 보낸다.

      {ref, {:ok, code}}
      {ref, {:error, :state_mismatch}}
      {ref, {:error, :missing_code}}

  `await_code/2`가 이 receive를 감싸주므로 일반적으로는 직접 메시지를
  볼 필요가 없다. 수동 붙여넣기 프롬프트와 경쟁시키는 것 같은 고급
  시나리오에서만 이 구조가 노출된다.
  """

  @default_port 1455
  @default_host {127, 0, 0, 1}
  @default_timeout 300_000

  @typedoc "`start/2`가 돌려주는 불투명 핸들."
  @type handle :: %{
          pid: pid,
          ref: reference,
          expected_state: String.t()
        }

  @doc """
  리스너를 시작하고 핸들을 반환한다.

  옵션:

    * `:port` — 바인딩할 TCP 포트(기본 `1455`). 프로바이더의 redirect
      URI가 1455로 등록되어 있으므로 이 값을 바꾸면 실제 OAuth 플로우가
      동작하지 않는다. 테스트 전용.
    * `:host` — 바인딩할 IP 튜플(기본 `{127, 0, 0, 1}`).
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
      plug: {Pado.LLMRouter.OAuth.Callback.Server.Plug, plug_opts},
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
  콜백 핸들러가 결과를 보낼 때까지 블로킹한다. 타임아웃이 지나면
  `{:error, :timeout}`을 반환한다.

  옵션:

    * `:timeout` — 밀리초(기본 `300_000`, 즉 5분).
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
  리스너를 종료한다. 여러 번 호출해도 안전하다.
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

  defp ensure_deps! do
    cond do
      not Code.ensure_loaded?(Bandit) ->
        raise """
        Pado.LLMRouter.OAuth.Callback.Server를 쓰려면 :bandit이 필요합니다.

        mix.exs에 다음을 추가하세요.

            {:bandit, "~> 1.5"},
            {:plug, "~> 1.16"}
        """

      not Code.ensure_loaded?(Plug) ->
        raise """
        Pado.LLMRouter.OAuth.Callback.Server를 쓰려면 :plug이 필요합니다.

        mix.exs에 다음을 추가하세요.

            {:plug, "~> 1.16"}
        """

      not Code.ensure_loaded?(Pado.LLMRouter.OAuth.Callback.Server.Plug) ->
        raise """
        Pado.LLMRouter.OAuth.Callback.Server.Plug가 컴파일되지 않았습니다.
        컴파일 시점에 :plug이 없었을 가능성이 큽니다. 의존성을 다시
        받고 재컴파일하세요.
        """

      true ->
        :ok
    end
  end
end

if Code.ensure_loaded?(Plug) do
  defmodule Pado.LLMRouter.OAuth.Callback.Server.Plug do
    @moduledoc false
    @behaviour Plug

    import Plug.Conn
    alias Pado.LLMRouter.OAuth.Callback.Page

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
          |> send_resp(400, Page.error_html("state 값이 일치하지 않습니다."))

        is_nil(code) or code == "" ->
          send(parent, {ref, {:error, :missing_code}})

          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> send_resp(400, Page.error_html("인가 코드가 전달되지 않았습니다."))

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
      |> send_resp(404, Page.error_html("콜백 경로를 찾을 수 없습니다."))
    end
  end
end
