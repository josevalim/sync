defmodule Sync.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    # TODO: Encapsulate this into Phoenix.Sync.Migrations.install()
    # TODO: We should consider using shared advisory locks to reduce
    # the "scope" of long running transactions
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
            DROP FUNCTION phx_sync_snap_columns();
            """

    # TODO: We need to either introduce sync_create or sync_table
    # that will add the relevant tables and triggers
    #
    # TODO: We also need to add soft deletion. Perhaps with views
    # and also a mechanism to scrape data on deletion. More info at:
    # https://evilmartians.com/chronicles/soft-deletion-with-postgresql-but-with-logic-on-the-database
    create table(:items) do
      add :name, :string
      add :done, :boolean, default: false, null: false

      add :_deleted_at, :utc_datetime
      add :_snapmin, :integer, null: false
      add :_snapcur, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    execute """
            CREATE TRIGGER phx_sync_snap_before_insert_update
            BEFORE INSERT OR UPDATE ON items
            FOR EACH ROW
            EXECUTE FUNCTION phx_sync_snap_columns();
            """,
            """
            DROP TRIGGER phx_sync_snap_before_insert_update ON items;
            """
  end
end
