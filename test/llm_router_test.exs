defmodule LLMRouterTest do
  use ExUnit.Case
  doctest LLMRouter

  test "greets the world" do
    assert LLMRouter.hello() == :world
  end
end
