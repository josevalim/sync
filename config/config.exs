# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sync,
  ecto_repos: [Sync.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :sync, SyncWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SyncWeb.ErrorHTML, json: SyncWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sync.PubSub,
  live_view: [signing_salt: "5gW26Rag"]

config :tailwind,
  version: "3.4.10",
  sync: [
    args: ~w(
      --config=tailwind.config.js
      --input=src/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sync, Sync.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
