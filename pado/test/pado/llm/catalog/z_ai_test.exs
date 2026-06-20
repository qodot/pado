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
end
