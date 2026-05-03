defmodule Pado.LLM.Message.User do
  alias Pado.LLM.Message

  @type t :: %__MODULE__{
          content: String.t() | [Message.content_part()],
          timestamp: DateTime.t() | nil
        }

  @enforce_keys [:content]
  defstruct [:content, timestamp: nil]

  def new(content) when is_binary(content) or is_list(content) do
    %__MODULE__{content: content, timestamp: DateTime.utc_now()}
  end
end
