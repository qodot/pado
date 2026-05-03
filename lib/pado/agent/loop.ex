defmodule Pado.Agent.Loop do
  alias Pado.Agent.{Event, Job}

  @type emit_fun :: (Event.t() -> any())

  @spec stream(Job.t()) :: Enumerable.t()
  def stream(%Job{} = _job) do
    raise "not implemented"
  end
end
