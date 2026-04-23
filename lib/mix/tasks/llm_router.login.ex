defmodule Mix.Tasks.LlmRouter.Login do
  @moduledoc """
  LLM OAuth 프로바이더에 로그인해 크레덴셜을 JSON으로 출력한다.

      $ mix llm_router.login                      # 기본값: openai-codex
      $ mix llm_router.login openai-codex
      $ mix llm_router.login --output creds.json

  라이브러리의 콜백 인터페이스를 터미널 I/O에 배선한 최소 레퍼런스 CLI다.
  pi-ai의 `packages/ai/src/cli.ts`와 대응된다.

  ## 왜 Mix task인가?

  공용 public OAuth 클라이언트의 `redirect_uri`가
  `http://localhost:1455/auth/callback`으로 등록되어 있기 때문에,
  로그인을 시작하는 머신에 브라우저가 있어야 한다. Mix task는 이
  요건과 잘 맞는다. 개발자가 수동으로 돌리고, 짧은 수명을 가지며,
  stdout에 접근할 수 있다.

  이 task는 **런타임에 크레덴셜을 쓰는 방법이 아니라** 발급 전용이다.
  출력된 JSON을 원하는 저장소(dotfile, Vault, 시크릿 매니저 등)에
  보관하고, 서비스 기동 시 그것을 로드한다.

  ## 옵션

    * `--output <path>` — stdout 대신 파일에 JSON을 쓴다.
    * `--originator <id>` — OAuth `originator` 파라미터를 덮어쓴다.
    * `--timeout <ms>` — 기본 5분 대기 시간을 덮어쓴다.
    * `--no-browser` — 브라우저 자동 열기를 끈다.
  """

  use Mix.Task

  alias LLMRouter.OAuth.Credentials

  @shortdoc "LLM OAuth 프로바이더에 로그인하고 크레덴셜을 JSON으로 출력한다"

  @provider_aliases %{
    "openai-codex" => LLMRouter.OAuth.OpenAICodex,
    "openai_codex" => LLMRouter.OAuth.OpenAICodex
  }

  @switches [
    output: :string,
    originator: :string,
    timeout: :integer,
    browser: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {:ok, _} = Application.ensure_all_started(:req)

    {opts, positional, _invalid} = OptionParser.parse(argv, switches: @switches)

    provider_mod = resolve_provider(positional)
    login_opts = build_login_opts(opts)
    open_browser? = Keyword.get(opts, :browser, true)

    callbacks = build_callbacks(open_browser?)

    case provider_mod.login(callbacks, login_opts) do
      {:ok, %Credentials{} = creds} ->
        write_output(creds, opts[:output])

      {:error, reason} ->
        Mix.shell().error("로그인 실패: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  # --- 배선 ---

  defp resolve_provider([]), do: LLMRouter.OAuth.OpenAICodex

  defp resolve_provider([alias_name | _]) do
    case Map.fetch(@provider_aliases, alias_name) do
      {:ok, mod} ->
        mod

      :error ->
        Mix.shell().error("알 수 없는 프로바이더: #{alias_name}")
        Mix.shell().info("사용 가능: #{Enum.join(Map.keys(@provider_aliases), ", ")}")
        exit({:shutdown, 1})
    end
  end

  defp build_login_opts(opts) do
    []
    |> put_if(:originator, opts[:originator])
    |> put_if(:timeout, opts[:timeout])
  end

  defp put_if(kw, _key, nil), do: kw
  defp put_if(kw, key, val), do: Keyword.put(kw, key, val)

  defp build_callbacks(open_browser?) do
    %{
      on_auth: fn %{url: url} = info ->
        instructions = Map.get(info, :instructions)
        Mix.shell().info("")
        Mix.shell().info("아래 URL을 브라우저에서 열어주세요:")
        Mix.shell().info(url)
        if instructions, do: Mix.shell().info(instructions)
        Mix.shell().info("")
        if open_browser?, do: try_open_browser(url)
      end,
      on_prompt: fn %{message: msg} ->
        answer = msg |> Mix.shell().prompt() |> String.trim()

        if answer == "" do
          {:error, :empty_input}
        else
          {:ok, answer}
        end
      end,
      on_progress: fn msg -> Mix.shell().info(msg) end
    }
  end

  defp try_open_browser(url) do
    {cmd, args} =
      case :os.type() do
        {:unix, :darwin} -> {"open", [url]}
        {:unix, _} -> {"xdg-open", [url]}
        {:win32, _} -> {"cmd", ["/c", "start", "", url]}
      end

    try do
      System.cmd(cmd, args, stderr_to_stdout: true)
      :ok
    catch
      :error, _ -> :ok
      :exit, _ -> :ok
    end
  end

  # --- 출력 ---

  defp write_output(%Credentials{} = creds, nil) do
    creds
    |> Credentials.to_map()
    |> Jason.encode!(pretty: true)
    |> IO.puts()
  end

  defp write_output(%Credentials{} = creds, path) do
    json =
      creds
      |> Credentials.to_map()
      |> Jason.encode!(pretty: true)

    File.write!(path, json)

    # 크레덴셜은 민감 정보이므로 권한을 조인다.
    _ = File.chmod(path, 0o600)

    Mix.shell().info("크레덴셜을 #{path} 에 기록했습니다.")
  end

  defp format_error(reason) when is_atom(reason) or is_binary(reason), do: inspect(reason)
  defp format_error({:token_request_failed, status, body}), do: "HTTP #{status}: #{inspect(body)}"
  defp format_error({:transport, %{__exception__: true} = e}), do: Exception.message(e)
  defp format_error(other), do: inspect(other)
end
