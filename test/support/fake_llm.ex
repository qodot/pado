defmodule Pado.Test.FakeLLM do
  # 테스트용 LLM 대체. 응답을 ETS 테이블에 owner pid 기준으로 저장하여
  # worker process(다른 PID)가 caller chain을 통해 owner를 찾아 응답을 조회한다.

  @table :pado_test_fake_llm

  def setup_owner do
    init_table()
    pid = self()
    :ets.insert(@table, {pid, :empty})
    pid
  end

  def cleanup_owner(pid \\ self()) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table, pid)
    end
  end

  def put_response(response) do
    init_table()
    :ets.insert(@table, {self(), {:single, response}})
  end

  def put_responses(responses) when is_list(responses) do
    init_table()
    :ets.insert(@table, {self(), {:queue, responses}})
  end

  def stream(model, ctx, creds, session_id, opts) do
    case find_owner() do
      nil ->
        {:error, :fake_router_no_owner}

      owner ->
        send(
          owner,
          {:fake_router_called,
           %{
             model: model,
             ctx: ctx,
             creds: creds,
             session_id: session_id,
             opts: opts
           }}
        )

        fetch_response(owner)
    end
  end

  defp init_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end
  end

  defp find_owner do
    callers = [self() | Process.get(:"$callers", [])]

    Enum.find(callers, fn pid ->
      case :ets.lookup(@table, pid) do
        [_] -> true
        _ -> false
      end
    end)
  end

  defp fetch_response(owner) do
    case :ets.lookup(@table, owner) do
      [{_, {:queue, [head | rest]}}] ->
        :ets.insert(@table, {owner, {:queue, rest}})
        head

      [{_, {:queue, []}}] ->
        {:error, :fake_router_queue_exhausted}

      [{_, {:single, response}}] ->
        response

      _ ->
        {:error, :fake_router_response_not_set}
    end
  end
end
