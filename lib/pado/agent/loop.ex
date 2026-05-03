defmodule Pado.Agent.Loop do
  alias Pado.Agent.{Event, Job}
  alias Pado.LLMRouter.Message.Assistant

  @type emit_fun :: (Event.t() -> any())

  @spec stream(Job.t()) :: Enumerable.t()
  def stream(%Job{} = _job) do
    raise "not implemented"
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
