import Config

config :sistema_emergencia, SistemaEmergenciaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SistemaEmergenciaWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: SistemaEmergencia.PubSub,
  live_view: [signing_salt: "emergencia_lv_salt_2026"],
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: "sistema_emergencia_secret_key_base_programacion_iii_elixir_phoenix_2026_seguro",
  server: Mix.env() != :test

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
