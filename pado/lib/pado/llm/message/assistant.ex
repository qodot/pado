defmodule Pado.LLM.Message.Assistant do
  alias Pado.LLM.{Message, Model, Usage}

  @type stop_reason :: :stop | :length | :tool_use | :aborted | :error | nil

  @type t :: %__MODULE__{
          content: [Message.content_part()],
          stop_reason: stop_reason,
          error_message: String.t() | nil,
          usage: Usage.t() | nil,
          provider: Model.provider() | nil,
          model: String.t() | nil,
          timestamp: DateTime.t() | nil
        }

  defstruct content: [],
            stop_reason: nil,
            error_message: nil,
            usage: nil,
            provider: nil,
            model: nil,
            timestamp: nil

  def init(%Model{} = m) do
    %__MODULE__{
      provider: m.provider,
      model: m.id,
      timestamp: DateTime.utc_now(),
      usage: Usage.empty()
    }
  end
end
