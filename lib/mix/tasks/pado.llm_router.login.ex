defmodule Mix.Tasks.Pado.LlmRouter.Login do
  use Mix.Task

  alias Pado.LLMRouter.OAuth.Credentials

  @provider_aliases %{
    "openai-codex" => Pado.LLMRouter.OAuth.OpenAICodex,
    "openai_codex" => Pado.LLMRouter.OAuth.OpenAICodex
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

  defp resolve_provider([]), do: Pado.LLMRouter.OAuth.OpenAICodex

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

    _ = File.chmod(path, 0o600)

    Mix.shell().info("크레덴셜을 #{path} 에 기록했습니다.")
  end

  defp format_error(reason) when is_atom(reason) or is_binary(reason), do: inspect(reason)
  defp format_error({:token_request_failed, status, body}), do: "HTTP #{status}: #{inspect(body)}"
  defp format_error({:transport, %{__exception__: true} = e}), do: Exception.message(e)
  defp format_error(other), do: inspect(other)
end
