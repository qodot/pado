defmodule Pado.Agent.Session do
  alias Pado.Agent.Session.Entry
  alias Pado.LLM.Catalog.OpenAICodex
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  @default_reasoning_effort :medium

  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          cwd: String.t() | nil,
          provider: atom() | nil,
          model: String.t() | nil,
          reasoning_effort: atom() | nil,
          entries: [Entry.t()],
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :created_at, :updated_at]
  defstruct [
    :id,
    :created_at,
    :updated_at,
    :cwd,
    :provider,
    :model,
    :reasoning_effort,
    version: 1,
    entries: []
  ]

  @spec new(String.t(), keyword()) :: t()
  def new(id, opts \\ []) when is_binary(id) and is_list(opts) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    default_model = default_model()

    %__MODULE__{
      id: id,
      cwd: Keyword.get(opts, :cwd, File.cwd!()),
      provider: Keyword.get(opts, :provider, default_model.provider),
      model: Keyword.get(opts, :model, default_model.id),
      reasoning_effort: Keyword.get(opts, :reasoning_effort, @default_reasoning_effort),
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  @spec to_llm_messages(t()) :: [Message.t()]
  def to_llm_messages(%__MODULE__{} = session) do
    session.entries
    |> Enum.flat_map(fn
      %Entry{kind: :user, payload: %User{} = message} -> [message]
      %Entry{kind: :assistant, payload: %Assistant{} = message} -> [message]
      %Entry{kind: :tool_result, payload: %ToolResult{} = message} -> [message]
      _ -> []
    end)
  end

  @spec append_messages(t(), [Message.t()], keyword()) :: {t(), [Entry.t()]}
  def append_messages(%__MODULE__{} = session, messages, opts \\ []) when is_list(messages) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    first_seq = next_seq(session)

    entries =
      messages
      |> Enum.with_index(first_seq)
      |> Enum.map(fn {message, seq} ->
        Entry.from_message(message, seq, timestamp: timestamp)
      end)

    {
      %{session | entries: session.entries ++ entries, updated_at: timestamp},
      entries
    }
  end

  defp next_seq(%__MODULE__{entries: []}), do: 0

  defp next_seq(%__MODULE__{entries: entries}) do
    entries
    |> List.last()
    |> Map.fetch!(:seq)
    |> Kernel.+(1)
  end

  defp default_model, do: OpenAICodex.default()
end
