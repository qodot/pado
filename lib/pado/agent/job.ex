defmodule Pado.Agent.Job do
  alias Pado.Agent.Tool
  alias Pado.LLMRouter.{Context, Model}
  alias Pado.LLMRouter.Credential.OAuth.Credentials

  @type credential_fun :: (-> {:ok, Credentials.t()} | {:error, term()})

  @type t :: %__MODULE__{
          model: Model.t(),
          credential_fun: credential_fun(),
          session_id: String.t(),
          context: Context.t(),
          tools: [Tool.t()],
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
    job_id: nil,
    llm_opts: [],
    max_turns: 10
  ]
end
