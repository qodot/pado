import Config

config :pado_cloud, PadoCloud.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pado_cloud_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :pado_cloud, PadoCloudWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "b41NqkmiWjwDAg82PuytOUByFwzT5hm8aslknR70VQjpkU1uknNNmPAKC/g1gPVR",
  server: false

config :pado_cloud, PadoCloud.Mailer, adapter: Swoosh.Adapters.Test

config :swoosh, :api_client, false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
