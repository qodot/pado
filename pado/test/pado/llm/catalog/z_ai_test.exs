defmodule Pado.LLM.Catalog.ZAITest do
  use ExUnit.Case, async: true

  alias Pado.LLM.Catalog.ZAI

  test "default/0은 Z.AI 기본 모델을 반환한다" do
    model = ZAI.default()

    assert model.id == "glm-5.2"
    assert model.provider == :z_ai
    assert model.base_url == "https://api.z.ai/api/paas/v4"
    assert model.supports_tools
    assert model.supports_reasoning
  end

  test "get/1은 모델별 context_window와 max_tokens를 반환한다" do
    assert ZAI.get("glm-5.2").context_window == 1_000_000
    assert ZAI.get("glm-5.1").context_window == 200_000
    assert ZAI.get("glm-5").context_window == 200_000
    assert ZAI.get("glm-4.7").context_window == 200_000

    assert Enum.all?(ZAI.all(), &(&1.max_tokens == 131_072))
  end

  test "ids/0은 등록된 Z.AI 모델 id를 반환한다" do
    assert ZAI.ids() |> Enum.sort() == ["glm-4.7", "glm-5", "glm-5.1", "glm-5.2"]
  end
end
