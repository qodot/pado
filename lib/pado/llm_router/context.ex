defmodule Pado.LLMRouter.Context do
  alias Pado.LLMRouter.{Message, Tool}

  @type t :: %__MODULE__{
          system_prompt: String.t() | nil,
          messages: [Message.t()],
          tools: [Tool.t()] | nil
        }

  defstruct system_prompt: nil, messages: [], tools: nil

  def new(opts \\ []) do
    %__MODULE__{
      system_prompt: Keyword.get(opts, :system_prompt),
      messages: Keyword.get(opts, :messages, []),
      tools: Keyword.get(opts, :tools)
    }
  end

  def append(%__MODULE__{messages: msgs} = ctx, message) do
    %__MODULE__{ctx | messages: msgs ++ [message]}
  end

  def append_all(%__MODULE__{messages: msgs} = ctx, new_msgs) when is_list(new_msgs) do
    %__MODULE__{ctx | messages: msgs ++ new_msgs}
  end

  def put_tools(%__MODULE__{} = ctx, tools), do: %__MODULE__{ctx | tools: tools}

  def put_system_prompt(%__MODULE__{} = ctx, prompt),
    do: %__MODULE__{ctx | system_prompt: prompt}

  def size(%__MODULE__{messages: m}), do: length(m)

  def last_message(%__MODULE__{messages: []}), do: nil
  def last_message(%__MODULE__{messages: m}), do: List.last(m)
end
