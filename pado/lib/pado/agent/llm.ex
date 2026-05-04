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

  @spec normalize_opts(keyword()) :: keyword()
  def normalize_opts(opts) do
    case Keyword.fetch(opts, :reasoning_effort) do
      :error ->
        opts

      {:ok, :none} ->
        Keyword.delete(opts, :reasoning_effort)

      {:ok, effort} when effort in [:low, :medium, :high, :xhigh] ->
        Keyword.put(opts, :reasoning_effort, Atom.to_string(effort))
    end
  end
end
