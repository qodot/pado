defmodule Pado.LLM.Credential.FileLoader do
  alias Pado.LLM.Credential.OAuth.{Credentials, OpenAICodex}

  def fetch(path) when is_binary(path) do
    with {:ok, json} <- File.read(path),
         {:ok, decoded} <- Jason.decode(json),
         {:ok, creds} <- Credentials.from_map(decoded) do
      maybe_refresh(creds, path)
    end
  end

  def save(%Credentials{} = creds, path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(Credentials.to_map(creds), pretty: true))
    _ = File.chmod(path, 0o600)
    :ok
  end

  defp maybe_refresh(%Credentials{} = creds, path) do
    if Credentials.stale?(creds, 60) do
      with {:ok, fresh} <- refresh(creds) do
        save(fresh, path)
        {:ok, fresh}
      end
    else
      {:ok, creds}
    end
  end

  defp refresh(%Credentials{provider: :openai_codex} = creds), do: OpenAICodex.refresh(creds)
  defp refresh(%Credentials{provider: other}), do: {:error, {:unsupported_provider, other}}
end
