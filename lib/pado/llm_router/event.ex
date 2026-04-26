defmodule Pado.LLMRouter.Event do
  alias Pado.LLMRouter.{Message, Usage}

  @type stop_reason :: Message.Assistant.stop_reason()

  @type t ::
          {:start, start_payload}
          | {:text_start, index_payload}
          | {:text_delta, delta_payload}
          | {:text_end, index_payload}
          | {:thinking_start, index_payload}
          | {:thinking_delta, delta_payload}
          | {:thinking_end, index_payload}
          | {:tool_call_start, tool_call_start_payload}
          | {:tool_call_delta, delta_payload}
          | {:tool_call_end, index_payload}
          | {:done, done_payload}
          | {:error, error_payload}

  @type start_payload :: %{message: Message.Assistant.t()}

  @type index_payload :: %{index: non_neg_integer}

  @type delta_payload :: %{
          index: non_neg_integer,
          delta: String.t()
        }

  @type tool_call_start_payload :: %{
          index: non_neg_integer,
          id: String.t(),
          name: String.t()
        }

  @type done_payload :: %{
          stop_reason: stop_reason,
          usage: Usage.t(),
          message: Message.Assistant.t()
        }

  @type error_payload :: %{
          reason: :error | :aborted,
          error_message: String.t(),
          message: Message.Assistant.t(),
          usage: Usage.t()
        }

  def terminal?({:done, _}), do: true
  def terminal?({:error, _}), do: true
  def terminal?(_), do: false

  def final_message({:done, %{message: m}}), do: m
  def final_message({:error, %{message: m}}), do: m
  def final_message(_), do: nil
end
