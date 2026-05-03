defmodule Pado.Agent.Turn do
  alias Pado.Agent.Event
  alias Pado.LLMRouter.Message
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}
  alias Pado.LLMRouter.Usage

  @type t :: %__MODULE__{
          index: pos_integer(),
          injected: [User.t()],
          assistant: Assistant.t(),
          tool_results: [ToolResult.t()],
          usage: Usage.t() | nil
        }

  @type emit_fun :: (Event.t() -> any())

  @enforce_keys [:index, :assistant]
  defstruct [:index, :assistant, injected: [], tool_results: [], usage: nil]

  @spec flatten(t()) :: [Message.t()]
  def flatten(%__MODULE__{injected: injected, assistant: assistant, tool_results: tool_results}) do
    injected ++ [assistant] ++ tool_results
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
