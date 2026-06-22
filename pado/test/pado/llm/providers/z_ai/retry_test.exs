defmodule Pado.LLM.Providers.ZAI.RetryTest do
  use ExUnit.Case, async: true

  alias Pado.LLM
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.User
  alias Pado.LLM.{Context, Model}

  defmodule RetryPlug do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, agent) do
      attempt = Agent.get_and_update(agent, fn count -> {count + 1, count + 1} end)

      if attempt == 1 do
        send_resp(conn, 500, "retry")
      else
        conn = send_chunked(conn, 200)
        {:ok, conn} = chunk(conn, sse(%{"choices" => [%{"index" => 0, "delta" => %{}}]}))

        {:ok, conn} =
          chunk(
            conn,
            sse(%{
              "choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => "stop"}],
              "usage" => %{
                "prompt_tokens" => 1,
                "completion_tokens" => 1,
                "total_tokens" => 2
              }
            })
          )

        {:ok, conn} = chunk(conn, "data: [DONE]\n\n")
        conn
      end
    end

    defp sse(data), do: "data: " <> Jason.encode!(data) <> "\n\n"
  end

  test "본문 수신 전 재시도 가능한 HTTP 오류는 재시도한다" do
    {:ok, _} = Application.ensure_all_started(:bandit)
    {:ok, _} = Application.ensure_all_started(:req)
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    {:ok, server} =
      Bandit.start_link(plug: {RetryPlug, agent}, port: 0, startup_log: false)

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    model = %Model{
      id: "glm-test",
      provider: :z_ai,
      base_url: "http://127.0.0.1:#{port}",
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    }

    credentials = Credentials.build(:z_ai, "api_dummy", "", 3600)

    {:ok, stream} =
      LLM.stream(model, Context.new(messages: [User.new("안녕")]), credentials, "session-1",
        max_retries: 1,
        retry_delay_ms: 0,
        receive_timeout: 5_000
      )

    assert [{:start, _}, {:done, %{stop_reason: :stop}}] = Enum.to_list(stream)
    assert Agent.get(agent, & &1) == 2

    GenServer.stop(server)
    Agent.stop(agent)
  end
end
