defmodule Pado.Agent.Turn do
  alias Pado.Agent.{Event, Job}
  alias Pado.LLMRouter.Message
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}
  alias Pado.LLMRouter.Usage

  @router Application.compile_env(:pado, :router, Pado.LLMRouter)

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

  @spec take(Job.t(), [t()], emit_fun) ::
          {:ok, t()} | {:error, t()} | {:error, term()}
  def take(%Job{} = job, prev_turns, emit) do
    index = length(prev_turns) + 1
    users = []

    msgs = job.context.messages ++ Enum.flat_map(prev_turns, &as_llm_messages/1) ++ users
    ctx = %{job.context | messages: msgs}

    with {:ok, creds} <- job.credential_fun.(),
         {:ok, stream} <-
           @router.stream(job.model, ctx, creds, job.session_id, job.llm_opts),
         {:ok, assistant} <- consume_llm_stream(stream, job.job_id, emit) do
      {:ok,
       %__MODULE__{
         index: index,
         users: users,
         assistant: assistant,
         tool_results: [],
         usage: assistant.usage
       }}
    else
      {:error, %Assistant{} = assistant} ->
        {:error,
         %__MODULE__{
           index: index,
           users: users,
           assistant: assistant,
           tool_results: [],
           usage: assistant.usage
         }}

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
end
