import Config

config :pado_local,
  generators: [timestamp_type: :utc_datetime]

config :pado,
  credentials: %{
    openai_codex:
      {Pado.LLM.Credential.FileLoader, Path.expand("~/.config/pado/openai_codex.json")}
  }

config :pado_local, PadoLocalWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PadoLocalWeb.ErrorHTML, json: PadoLocalWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PadoLocal.PubSub,
  live_view: [signing_salt: "GgmZu8Jv"]

config :esbuild,
  version: "0.25.4",
  pado_local: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  pado_local: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
