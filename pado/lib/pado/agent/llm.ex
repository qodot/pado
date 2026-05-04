defmodule Pado.Agent.LLM do
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Model

  @type t :: %__MODULE__{
          provider: atom(),
          router: module(),
          credentials: Credentials.t(),
          model: Model.t(),
          opts: keyword()
        }

  @enforce_keys [:provider, :credentials, :model]
  defstruct [
    :provider,
    :credentials,
    :model,
    router: Application.compile_env(:pado, :router, Pado.LLM),
    opts: []
  ]
end
