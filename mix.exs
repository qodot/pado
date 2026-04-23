defmodule LLMRouter.MixProject do
  use Mix.Project

  def project do
    [
      app: :llm_router,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},

      # OAuth callback server (optional — only required when calling
      # LLMRouter.OAuth.*.login/2 or using `mix llm_router.login`).
      {:bandit, "~> 1.5", optional: true},
      {:plug, "~> 1.16", optional: true},

      # Dev/test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
