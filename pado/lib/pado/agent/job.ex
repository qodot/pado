defmodule Pado.Agent.Job do
  alias Pado.Agent.Turn
  alias Pado.AgentConfig
  alias Pado.LLM.Message, as: LLMMessage

  @type t :: %__MODULE__{
          messages: [LLMMessage.t()],
          session_id: String.t(),
          turns: [Turn.t()],
          job_id: String.t() | nil,
          max_turns: pos_integer()
        }

  @type next_decision :: :continue | :done | :max_turns

  @enforce_keys [:messages, :session_id]
  defstruct [
    :messages,
    :session_id,
    turns: [],
    job_id: nil,
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

  @spec next_step(t()) :: next_decision()
  def next_step(%__MODULE__{turns: turns, max_turns: max}) do
    cond do
      length(turns) >= max -> :max_turns
      has_tool_calls?(List.last(turns)) -> :continue
      true -> :done
    end
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

  defp has_tool_calls?(nil), do: false
  defp has_tool_calls?(%Turn{assistant: assistant}), do: Turn.tool_calls(assistant) != []
end
