defmodule Pado.Test.FakeCredsLoader do
  # 테스트용 Credential loader. 응답을 ETS 테이블에 owner pid 기준으로 저장하여
  # worker process(다른 PID)가 caller chain을 통해 owner를 찾아 응답을 조회한다.

  @table :pado_test_fake_creds

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
    :ets.insert(@table, {self(), response})
  end

  def load(_arg) do
    case find_owner() do
      nil ->
        {:error, :fake_creds_no_owner}

      owner ->
        case :ets.lookup(@table, owner) do
          [{_, response}] -> response
          _ -> {:error, :fake_creds_response_not_set}
        end
    end
  end

  def save(creds, _arg) do
    if owner = find_owner() do
      send(owner, {:fake_creds_save, creds})
    end

    :ok
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
end
