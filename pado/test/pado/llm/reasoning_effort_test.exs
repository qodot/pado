defmodule Pado.LLM.ReasoningEffortTest do
  use ExUnit.Case, async: true

  alias Pado.LLM.ReasoningEffort

  test "normalize/1은 지원하는 값을 문자열로 정규화한다" do
    assert ReasoningEffort.normalize(:none) == "none"
    assert ReasoningEffort.normalize(:low) == "low"
    assert ReasoningEffort.normalize(:medium) == "medium"
    assert ReasoningEffort.normalize(:high) == "high"
    assert ReasoningEffort.normalize(:xhigh) == "xhigh"
    assert ReasoningEffort.normalize("minimal") == "minimal"
    assert ReasoningEffort.normalize("max") == "max"
  end

  test "normalize/1은 알 수 없는 값을 nil로 정규화한다" do
    assert ReasoningEffort.normalize(:unknown) == nil
    assert ReasoningEffort.normalize("unknown") == nil
    assert ReasoningEffort.normalize(1) == nil
  end
end
