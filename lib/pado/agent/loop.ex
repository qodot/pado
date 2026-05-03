defmodule Pado.Agent.Loop do
  alias Pado.Agent.Job

  @spec stream(Job.t()) :: Enumerable.t()
  def stream(%Job{} = _job) do
    raise "not implemented"
  end
end
