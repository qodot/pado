defmodule Pado.Agent.Turn do
  alias Pado.Agent
  alias Pado.Agent.{Event, Job}
  alias Pado.Agent.Tools.Tool
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult}
  alias Pado.LLM.Usage

  @type t :: %__MODULE__{
          index: pos_integer(),
          assistant: Assistant.t(),
          tool_results: [ToolResult.t()],
          usage: Usage.t() | nil
        }

  @type send_event_fun :: (Event.t() -> any())

  @enforce_keys [:index, :assistant]
  defstruct [:index, :assistant, tool_results: [], usage: nil]

  @spec as_llm_messages(t()) :: [Message.t()]
  def as_llm_messages(%__MODULE__{assistant: assistant, tool_results: tool_results}) do
    [assistant] ++ tool_results
  end

  @spec take(Agent.t(), Job.t(), send_event_fun) :: {:ok, Job.t()} | {:error, Job.t()}
  def take(%Agent{} = agent, %Job{} = job, send_event) do
    turn_index = length(job.turns) + 1
    llm = agent.llm

    send_event.({:turn_start, %{job_id: job.job_id, turn_index: turn_index}})

    with {:ok, stream} <-
           llm.router.stream(
             llm.model,
             Agent.llm_context(agent, job),
             llm.credentials,
             job.session_id,
             llm.opts
           ),
         {:ok, assistant} <- consume_llm_stream(stream, job.job_id, send_event) do
      tool_results = dispatch_tools(agent, job, assistant, turn_index, send_event)

      turn = build_turn(turn_index, assistant, tool_results)
      send_event.({:turn_end, %{job_id: job.job_id, turn: turn}})
      {:ok, %{job | turns: job.turns ++ [turn]}}
    else
      {:error, %Assistant{} = assistant} ->
        turn = build_turn(turn_index, assistant, [])
        send_event.({:turn_end, %{job_id: job.job_id, turn: turn}})
        {:error, %{job | turns: job.turns ++ [turn]}}

      {:error, reason} ->
        error_message =
          case reason do
            reason when is_binary(reason) -> reason
            reason when is_atom(reason) -> Atom.to_string(reason)
            _ -> inspect(reason)
          end

        assistant = %Assistant{stop_reason: :error, error_message: error_message}

        turn = build_turn(turn_index, assistant, [])
        send_event.({:turn_end, %{job_id: job.job_id, turn: turn}})
        {:error, %{job | turns: job.turns ++ [turn]}}
    end
  end

  @doc false
  @spec consume_llm_stream(Enumerable.t(), Event.job_id(), send_event_fun) ::
          {:ok, Assistant.t()} | {:error, Assistant.t()}
  def consume_llm_stream(stream, job_id, send_event) do
    send_update = &send_event.({:message_update, %{job_id: job_id, llm_event: &1}})

    stream
    |> Enum.reduce_while(nil, fn
      {:start, %{message: msg}} = event, _ ->
        send_event.({:message_start, %{job_id: job_id, message: msg}})
        send_update.(event)
        {:cont, nil}

      {:done, %{message: msg}} = event, _ ->
        send_update.(event)
        send_event.({:message_end, %{job_id: job_id, message: msg}})
        {:halt, {:ok, msg}}

      {:error, %{message: msg}} = event, _ ->
        send_update.(event)
        send_event.({:message_end, %{job_id: job_id, message: msg}})
        {:halt, {:error, msg}}

      event, _ ->
        send_update.(event)
        {:cont, nil}
    end)
    |> finalize_consume()
  end

  defp finalize_consume(nil) do
    msg = %Assistant{
      stop_reason: :error,
      error_message: "stream ended without :done or :error"
    }

    {:error, msg}
  end

  defp finalize_consume(result), do: result

  defp dispatch_tools(
         %Agent{} = agent,
         %Job{} = job,
         %Assistant{} = assistant,
         turn_index,
         send_event
       ) do
    assistant
    |> tool_calls()
    |> Enum.map(fn call ->
      send_event.(
        {:tool_execution_start,
         %{
           job_id: job.job_id,
           turn_index: turn_index,
           tool_call_id: call.id,
           tool_name: call.name,
           args: call.args
         }}
      )

      result = dispatch_tool(call, agent.harness.tools)

      send_event.(
        {:tool_execution_end,
         %{
           job_id: job.job_id,
           turn_index: turn_index,
           tool_call_id: call.id,
           tool_name: call.name,
           result: result,
           is_error: result.is_error
         }}
      )

      result
    end)
  end

  @doc false
  @spec tool_calls(Assistant.t()) :: [Message.tool_call()]
  def tool_calls(%Assistant{content: content}) do
    Enum.flat_map(content, fn
      {:tool_call, call} -> [call]
      _ -> []
    end)
  end

  @doc false
  @spec find_tool([Tool.t()], String.t()) :: Tool.t() | nil
  def find_tool(tools, name) when is_list(tools) and is_binary(name) do
    Enum.find(tools, fn %Tool{schema: schema} -> schema.name == name end)
  end

  @doc false
  @spec dispatch_tool(Message.tool_call(), [Tool.t()]) :: ToolResult.t()
  def dispatch_tool(%{id: id, name: name, args: args}, tools) do
    case find_tool(tools, name) do
      nil ->
        ToolResult.error(id, name, "unknown tool: #{name}")

      %Tool{execute: execute} ->
        try do
          output = execute.(args, %{})
          text = if is_binary(output), do: output, else: inspect(output)
          ToolResult.text(id, name, text)
        rescue
          e -> ToolResult.error(id, name, Exception.message(e))
        end
    end
  end

  defp build_turn(turn_index, %Assistant{} = assistant, tool_results) do
    %__MODULE__{
      index: turn_index,
      assistant: assistant,
      tool_results: tool_results,
      usage: assistant.usage
    }
  end
end
