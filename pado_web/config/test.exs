import Config

config :pado_web, PadoWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Pqf2z6JzvQfvbIy+ytcZ0/hxCM1dhb660LIbqilxyph9Hvip/lZzh3r6EAvkHX+e",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
