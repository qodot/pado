defmodule Pado.Agent do
  alias Pado.Agent.{Event, Harness, Job, LLM, Tool, Turn}
  alias Pado.LLM.Context, as: LLMContext

  @type send_event_fun :: (Event.t() -> any())

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          llm: LLM.t(),
          harness: Harness.t()
        }

  @enforce_keys [:llm, :harness]
  defstruct [
    :llm,
    :harness,
    name: nil,
    description: nil
  ]

  @spec llm_context(t(), Job.t()) :: LLMContext.t()
  def llm_context(%__MODULE__{} = agent, %Job{} = job) do
    %LLMContext{
      system_prompt: agent.harness.system_prompt,
      messages: Job.llm_messages(job),
      tools: Enum.map(agent.harness.tools, &Tool.as_llm_tool/1)
    }
  end

  @spec stream(t(), Job.t()) :: Enumerable.t()
  def stream(%__MODULE__{} = agent, %Job{} = job) do
    Stream.resource(
      fn -> start_worker(agent, job) end,
      &receive_event/1,
      &cleanup/1
    )
  end

  defp start_worker(agent, %Job{} = job) do
    owner = self()
    ref = make_ref()
    send_event = fn event -> send(owner, {ref, event}) end

    worker =
      Task.async(fn ->
        send_event.({:job_start, %{job_id: job.job_id}})
        {final_job, status, reason} = loop(agent, job, send_event)

        send_event.(
          {:job_end,
           %{
             job_id: final_job.job_id,
             status: status,
             reason: reason,
             turns: final_job.turns
           }}
        )
      end)

    %{ref: ref, worker: worker, halted: false}
  end

  defp receive_event(%{halted: true} = state), do: {:halt, state}

  defp receive_event(%{ref: ref} = state) do
    receive do
      {^ref, event} ->
        if Event.terminal?(event) do
          {[event], %{state | halted: true}}
        else
          {[event], state}
        end
    end
  end

  defp cleanup(%{worker: worker}) do
    Task.shutdown(worker, :brutal_kill)
    :ok
  end

  @spec loop(t(), Job.t(), send_event_fun) :: {Job.t(), Event.status(), term() | nil}
  def loop(%__MODULE__{} = agent, %Job{} = job, send_event) do
    case Turn.take(agent, job, send_event) do
      {:ok, job} ->
        case Job.next_step(job) do
          :continue -> loop(agent, job, send_event)
          status -> {job, status, nil}
        end

      {:error, %Job{} = job} ->
        reason = List.last(job.turns).assistant.error_message
        {job, :error, reason}
    end
  end
end
