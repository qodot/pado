defmodule Mix.Tasks.LlmRouter.Login do
  @moduledoc """
  Logs in to an LLM OAuth provider and prints the resulting credentials
  as JSON on stdout.

      $ mix llm_router.login                      # defaults to openai-codex
      $ mix llm_router.login openai-codex
      $ mix llm_router.login --output creds.json

  The task is the minimal reference CLI that wires the library's
  callback interface to terminal I/O. Mirrors pi-ai's `packages/ai/src/cli.ts`.

  ## Why is this a Mix task?

  Because the OAuth `redirect_uri` for the shared public OAuth clients
  is registered as `http://localhost:1455/auth/callback`, the browser
  used for login must be on the same machine that runs this task. Mix
  tasks are a natural fit: developer-operated, short-lived, with access
  to stdout.

  The task is **not** how you consume credentials at runtime: it only
  mints them. Persist the printed JSON somewhere (a dotfile, Vault,
  secrets manager) and load it into your running service at boot.

  ## Options

    * `--output <path>` — write JSON to a file instead of stdout.
    * `--originator <id>` — override the OAuth `originator` parameter.
    * `--timeout <ms>` — override the 5-minute default wait.
    * `--no-browser` — do not attempt to open a browser automatically.
  """

  use Mix.Task

  alias LLMRouter.OAuth.Credentials

  @shortdoc "Login to an LLM OAuth provider; print credentials as JSON"

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
        Mix.shell().error("Login failed: #{format_error(reason)}")
        exit({:shutdown, 1})
    end
  end

  # --- wiring ---

  defp resolve_provider([]), do: LLMRouter.OAuth.OpenAICodex

  defp resolve_provider([alias_name | _]) do
    case Map.fetch(@provider_aliases, alias_name) do
      {:ok, mod} ->
        mod

      :error ->
        Mix.shell().error("Unknown provider: #{alias_name}")
        Mix.shell().info("Available: #{Enum.join(Map.keys(@provider_aliases), ", ")}")
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
        Mix.shell().info("Open this URL in your browser:")
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

  # --- output ---

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

    # Tighten permissions — credentials are sensitive.
    _ = File.chmod(path, 0o600)

    Mix.shell().info("Credentials written to #{path}")
  end

  defp format_error(reason) when is_atom(reason) or is_binary(reason), do: inspect(reason)
  defp format_error({:token_request_failed, status, body}), do: "HTTP #{status}: #{inspect(body)}"
  defp format_error({:transport, %{__exception__: true} = e}), do: Exception.message(e)
  defp format_error(other), do: inspect(other)
end
