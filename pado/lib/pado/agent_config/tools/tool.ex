defmodule Pado.AgentConfig.Tools.Tool do
  alias Pado.LLM.Tool, as: RouterTool

  @type update_fun :: (__MODULE__.Result.t() -> any())
  @type async_fun :: (map(), map(), update_fun() -> Task.t())
  @type abort_fun :: (Task.t() -> any())

  @type t :: %__MODULE__{
          schema: RouterTool.t(),
          async: async_fun(),
          abort: abort_fun()
        }

  @enforce_keys [:schema, :async, :abort]
  defstruct [:schema, :async, :abort]

  @spec as_llm_tool(t()) :: RouterTool.t()
  def as_llm_tool(%__MODULE__{schema: schema}), do: schema

  defmodule Result do
    alias Pado.LLM.Message

    @type t :: %__MODULE__{
            content: [Message.content_part()],
            details: term(),
            terminate: boolean()
          }

    defstruct content: [], details: %{}, terminate: false

    @spec text(String.t(), keyword()) :: t()
    def text(text, opts \\ []) when is_binary(text) do
      %__MODULE__{
        content: [{:text, text}],
        details: Keyword.get(opts, :details, %{}),
        terminate: Keyword.get(opts, :terminate, false)
      }
    end

    @spec from_output(t() | term()) :: t()
    def from_output(%__MODULE__{} = result), do: result
    def from_output(output) when is_binary(output), do: text(output)
    def from_output(output), do: output |> inspect() |> text()
  end
end
