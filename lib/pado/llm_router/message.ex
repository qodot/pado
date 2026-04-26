defmodule Pado.LLMRouter.Message do
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}

  @type role :: :user | :assistant | :tool_result

  @type t :: User.t() | Assistant.t() | ToolResult.t()

  @type content_part ::
          {:text, String.t()}
          | {:thinking, String.t()}
          | {:image, image_data}
          | {:tool_call, tool_call}

  @type image_data :: %{media_type: String.t(), data: binary}

  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          args: map
        }

  def role(%User{}), do: :user
  def role(%Assistant{}), do: :assistant
  def role(%ToolResult{}), do: :tool_result

  def text(%User{content: content}) when is_binary(content), do: content
  def text(%User{content: parts}), do: join_text(parts)
  def text(%Assistant{content: parts}), do: join_text(parts)
  def text(%ToolResult{content: parts}), do: join_text(parts)

  defp join_text(parts) when is_list(parts) do
    parts
    |> Enum.flat_map(fn
      {:text, t} -> [t]
      _ -> []
    end)
    |> Enum.join()
  end
end
