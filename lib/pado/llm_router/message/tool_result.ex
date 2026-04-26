defmodule Pado.LLMRouter.Message.ToolResult do
  alias Pado.LLMRouter.Message

  @type t :: %__MODULE__{
          tool_call_id: String.t(),
          tool_name: String.t(),
          content: [Message.content_part()],
          is_error: boolean,
          timestamp: DateTime.t() | nil
        }

  @enforce_keys [:tool_call_id, :tool_name]
  defstruct [
    :tool_call_id,
    :tool_name,
    content: [],
    is_error: false,
    timestamp: nil
  ]

  def text(tool_call_id, tool_name, text, opts \\ []) when is_binary(text) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      content: [{:text, text}],
      is_error: Keyword.get(opts, :is_error, false),
      timestamp: DateTime.utc_now()
    }
  end

  def error(tool_call_id, tool_name, message) when is_binary(message) do
    text(tool_call_id, tool_name, message, is_error: true)
  end
end
