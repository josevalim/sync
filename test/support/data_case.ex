defmodule Sync.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Sync.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  # We cannot use the sandbox because it wraps everything in a single transaction
  # and PG snapshot functionality does not work. So we do it manually.
  setup tags do
    Sync.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    if tags[:async] do
      raise "cannot have async tests with replication connection"
    end

    Ecto.Adapters.SQL.Sandbox.checkout(Sync.Repo, sandbox: false)

    if cleanup = tags[:cleanup] do
      on_exit(fn ->
        Ecto.Adapters.SQL.Sandbox.checkout(Sync.Repo, sandbox: false)
        Sync.Repo.query!("TRUNCATE ONLY #{Enum.join(cleanup, ",")}")
      end)
    end

    :ok
  end
end
