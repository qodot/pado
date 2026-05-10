defmodule Pado.Agent.Job do
  alias Pado.Agent.Turn
  alias Pado.AgentConfig
  alias Pado.LLM.Message, as: LLMMessage

  @type t :: %__MODULE__{
          session_id: String.t(),
          job_id: String.t() | nil,
          messages: [LLMMessage.t()],
          turns: [Turn.t()],
          running_tools: map(),
          max_turns: pos_integer()
        }

  @enforce_keys [:messages, :session_id]
  defstruct [
    :session_id,
    :job_id,
    messages: [],
    turns: [],
    running_tools: %{},
    max_turns: 10
  ]

  @spec llm_messages(t()) :: [LLMMessage.t()]
  def llm_messages(%__MODULE__{} = job) do
    job.messages ++ Enum.flat_map(job.turns, &Turn.as_llm_messages/1)
  end

  @spec run(t(), AgentConfig.t(), [pid()], (term() -> any())) :: {pid(), reference()}
  def run(%__MODULE__{} = job, %AgentConfig{} = config, callers, send_job_event) do
    {pid, ref} =
      spawn_monitor(fn ->
        Process.put(:"$callers", callers)

        {status, reason, job} = take_turn(job, config, send_job_event)

        send_job_event.(
          {:job_end,
           %{
             job_id: job.job_id,
             status: status,
             reason: reason,
             turns: job.turns,
             job: job
           }}
        )
      end)

    {pid, ref}
  end

  @spec cancel(pid() | nil, reference() | nil) :: :ok
  def cancel(nil, _monitor_ref), do: :ok

  def cancel(pid, monitor_ref) when is_pid(pid) and is_reference(monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    Process.exit(pid, :shutdown)
    :ok
  end

  defp take_turn(job, config, send_job_event) do
    case Turn.take(config, job, send_job_event) do
      {:ok, job} ->
        case next_step(job) do
          :continue -> take_turn(job, config, send_job_event)
          status -> {status, nil, job}
        end

      {:error, job} ->
        reason = List.last(job.turns).assistant.error_message
        {:error, reason, job}
    end
  end

  defp next_step(%__MODULE__{turns: turns, max_turns: max}) do
    cond do
      length(turns) >= max -> :max_turns
      has_tool_calls?(List.last(turns)) -> :continue
      true -> :done
    end
  end

  defp has_tool_calls?(nil), do: false
  defp has_tool_calls?(%Turn{assistant: assistant}), do: Turn.tool_calls(assistant) != []
end
