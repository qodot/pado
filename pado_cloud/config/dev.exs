import Config

config :pado_cloud, PadoCloud.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "pado_cloud_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :pado_cloud, PadoCloudWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "kWD1mVrz3GprjvMOCwDlqsqeI4vJqevnZC5R+gl8K3/O7LtsMt5VfqdZoYtNfA7E",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:pado_cloud, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:pado_cloud, ~w(--watch)]}
  ]

config :pado_cloud, PadoCloudWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"priv/gettext/.*\.po$"E,
      ~r"lib/pado_cloud_web/router\.ex$"E,
      ~r"lib/pado_cloud_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :pado_cloud, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
