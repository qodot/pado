defmodule Pado.Agent.Job do
  alias Pado.Agent.{Tool, Turn}
  alias Pado.LLM.{Context, Message, Model}
  alias Pado.LLM.Credential.OAuth.Credentials

  @type credential_fun :: (-> {:ok, Credentials.t()} | {:error, term()})

  @type t :: %__MODULE__{
          model: Model.t(),
          credential_fun: credential_fun(),
          session_id: String.t(),
          context: Context.t(),
          tools: [Tool.t()],
          turns: [Turn.t()],
          job_id: String.t() | nil,
          llm_opts: keyword(),
          max_turns: pos_integer()
        }

  @enforce_keys [:model, :credential_fun, :session_id, :context]
  defstruct [
    :model,
    :credential_fun,
    :session_id,
    :context,
    tools: [],
    turns: [],
    job_id: nil,
    llm_opts: [],
    max_turns: 10
  ]

  @spec llm_messages(t()) :: [Message.t()]
  def llm_messages(%__MODULE__{} = job) do
    job.context.messages ++ Enum.flat_map(job.turns, &Turn.as_llm_messages/1)
  end
end
