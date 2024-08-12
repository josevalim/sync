defmodule Sync.Repo.Migrations.CreatePublication do
  use Ecto.Migration

  def change do
    # TODO: Encapsulate this into Phoenix.Sync.Migrations.create_publication()
    # Perhaps make it an Ecto feature?
    execute "CREATE PUBLICATION phx_sync",
            "DROP PUBLICATION phx_sync"

    # TODO: Encapsulate this into Phoenix.Sync.Migrations.install_sync()
    # TODO: We should consider using shared advisory locks to reduce
    # the "scope" of long running transactions
    # TODO: We may not need the _snapcur column
    execute """
            CREATE OR REPLACE FUNCTION phx_sync_snap_columns()
            RETURNS TRIGGER AS $$
            BEGIN
                NEW._snapcur := pg_current_xact_id();
                NEW._snapmin := pg_snapshot_xmin(pg_current_snapshot());
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
            """,
            """
            DROP FUNCTION IF EXISTS phx_sync_snap_columns();
            """
  end
end
