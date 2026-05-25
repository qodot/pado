defmodule Pado.LLM.Providers.OpenAICodex.StreamTest do
  use ExUnit.Case, async: false

  alias Pado.LLM
  alias Pado.LLM.{Context, Model}
  alias Pado.LLM.Credential.OAuth.Credentials

  test "Finch 요청에 수신 timeout을 전달한다" do
    model = %Model{
      id: "gpt-test",
      provider: :openai_codex,
      base_url: "http://127.0.0.1:1",
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    }

    credentials =
      Credentials.build(:openai_codex, "access_dummy", "refresh_dummy", 3600, %{
        "account_id" => "acct_dummy"
      })

    parent = self()

    pid =
      spawn_link(fn ->
        receive do
          :run ->
            result =
              LLM.stream(model, Context.new(), credentials, "session-1",
                max_retries: 0,
                receive_timeout: 1_234
              )

            send(parent, {:stream_result, result})
        end
      end)

    :erlang.trace(pid, true, [:call])
    :erlang.trace_pattern({Finch, :async_request, 3}, [{:_, [], []}], [:global])

    on_exit(fn ->
      :erlang.trace_pattern({Finch, :async_request, 3}, false, [:global])
    end)

    send(pid, :run)

    assert_receive {:trace, ^pid, :call,
                    {Finch, :async_request, [_request, Req.Finch, receive_opts]}},
                   1_000

    assert Keyword.fetch!(receive_opts, :receive_timeout) == 1_234
    assert_receive {:stream_result, {:ok, %Pado.LLM.Stream{}}}, 1_000
  end
end
