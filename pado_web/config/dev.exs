import Config

config :pado_web, PadoWebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "oUQZ0HwmxNS0wtINA4x4Xx7zikWpv4q5jnDyLMh/8sOH5SNsRKlO6d0dOeZYNj3y",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:pado_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:pado_web, ~w(--watch)]}
  ]

config :pado_web, PadoWebWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"priv/gettext/.*\.po$"E,
      ~r"lib/pado_web_web/router\.ex$"E,
      ~r"lib/pado_web_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :pado_web, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
