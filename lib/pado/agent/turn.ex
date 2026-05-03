defmodule Pado.Agent.Turn do
  alias Pado.Agent.{Event, Job, Tool}
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult, User}
  alias Pado.LLM.Usage

  @router Application.compile_env(:pado, :router, Pado.LLM)

  @type t :: %__MODULE__{
          index: pos_integer(),
          users: [User.t()],
          assistant: Assistant.t(),
          tool_results: [ToolResult.t()],
          usage: Usage.t() | nil
        }

  @type emit_fun :: (Event.t() -> any())

  @enforce_keys [:index, :assistant]
  defstruct [:index, :assistant, users: [], tool_results: [], usage: nil]

  @spec as_llm_messages(t()) :: [Message.t()]
  def as_llm_messages(%__MODULE__{users: users, assistant: assistant, tool_results: tool_results}) do
    users ++ [assistant] ++ tool_results
  end

  @spec take(Job.t(), emit_fun) ::
          {:ok, Job.t()} | {:error, Job.t()} | {:error, term()}
  def take(%Job{} = job, emit) do
    index = length(job.turns) + 1
    users = []

    with {:ok, creds} <- job.credential_fun.(),
         {:ok, stream} <-
           @router.stream(job.model, Job.llm_context(job), creds, job.session_id, job.llm_opts),
         {:ok, assistant} <- consume_llm_stream(stream, job.job_id, emit) do
      tool_results = dispatch_tools(assistant, job, index, emit)

      turn = %__MODULE__{
        index: index,
        users: users,
        assistant: assistant,
        tool_results: tool_results,
        usage: assistant.usage
      }

      {:ok, %{job | turns: job.turns ++ [turn]}}
    else
      {:error, %Assistant{} = assistant} ->
        turn = %__MODULE__{
          index: index,
          users: users,
          assistant: assistant,
          tool_results: [],
          usage: assistant.usage
        }

        {:error, %{job | turns: job.turns ++ [turn]}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec consume_llm_stream(Enumerable.t(), Event.job_id(), emit_fun) ::
          {:ok, Assistant.t()} | {:error, Assistant.t()}
  def consume_llm_stream(stream, job_id, emit) do
    emit_update = &emit.({:message_update, %{job_id: job_id, llm_event: &1}})

    stream
    |> Enum.reduce_while(nil, fn
      {:start, %{message: msg}} = ev, _ ->
        emit.({:message_start, %{job_id: job_id, message: msg}})
        emit_update.(ev)
        {:cont, nil}

      {:done, %{message: msg}} = ev, _ ->
        emit_update.(ev)
        emit.({:message_end, %{job_id: job_id, message: msg}})
        {:halt, {:ok, msg}}

      {:error, %{message: msg}} = ev, _ ->
        emit_update.(ev)
        emit.({:message_end, %{job_id: job_id, message: msg}})
        {:halt, {:error, msg}}

      ev, _ ->
        emit_update.(ev)
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

  defp dispatch_tools(%Assistant{} = assistant, %Job{} = job, index, emit) do
    assistant
    |> tool_calls()
    |> Enum.map(fn call ->
      emit.(
        {:tool_execution_start,
         %{
           job_id: job.job_id,
           turn_index: index,
           tool_call_id: call.id,
           tool_name: call.name,
           args: call.args
         }}
      )

      result = dispatch_tool(call, job.tools)

      emit.(
        {:tool_execution_end,
         %{
           job_id: job.job_id,
           turn_index: index,
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
end
