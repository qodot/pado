defmodule Pado.Agent.Session.Store do
  alias Pado.Agent.Session
  alias Pado.Agent.Session.Entry
  alias Pado.Agent.Session.Summary

  @type t :: {module(), keyword()}

  @callback list(keyword()) :: {:ok, [Summary.t()]} | {:error, term()}
  @callback load(String.t(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  @callback save(Session.t(), keyword()) :: :ok | {:error, term()}
  @callback append(String.t(), [Entry.t()], keyword()) :: :ok | {:error, term()}

  @spec list(t()) :: {:ok, [Summary.t()]} | {:error, term()}
  def list({module, opts}) when is_atom(module) and is_list(opts) do
    module.list(opts)
  end

  @spec load(t(), String.t()) :: {:ok, Session.t()} | {:error, term()}
  def load({module, opts}, session_id) when is_atom(module) and is_list(opts) do
    module.load(session_id, opts)
  end

  @spec save(t(), Session.t()) :: :ok | {:error, term()}
  def save({module, opts}, %Session{} = session) when is_atom(module) and is_list(opts) do
    module.save(session, opts)
  end

  @spec append(t(), String.t(), Entry.t() | [Entry.t()]) :: :ok | {:error, term()}
  def append({module, opts}, session_id, %Entry{} = entry)
      when is_atom(module) and is_list(opts) do
    append({module, opts}, session_id, [entry])
  end

  def append({module, opts}, session_id, entries)
      when is_atom(module) and is_binary(session_id) and is_list(opts) and is_list(entries) do
    module.append(session_id, entries, opts)
  end
end
