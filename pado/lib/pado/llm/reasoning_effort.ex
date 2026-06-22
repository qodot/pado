defmodule Pado.LLM.ReasoningEffort do
  def normalize(nil), do: nil
  def normalize(:none), do: "none"
  def normalize(:low), do: "low"
  def normalize(:medium), do: "medium"
  def normalize(:high), do: "high"
  def normalize(:xhigh), do: "xhigh"
  def normalize("none"), do: "none"
  def normalize("minimal"), do: "minimal"
  def normalize("low"), do: "low"
  def normalize("medium"), do: "medium"
  def normalize("high"), do: "high"
  def normalize("xhigh"), do: "xhigh"
  def normalize("max"), do: "max"
  def normalize(_), do: nil
end
