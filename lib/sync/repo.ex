defmodule Sync.Repo do
  use Ecto.Repo,
    otp_app: :sync,
    adapter: Ecto.Adapters.Postgres
end
