defmodule Sync.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    # TODO: We need to either introduce sync_create or a syncify
    # function that wil add the relevant tables and triggers.
    # If we go with syncify, we need to guarantee "idempotency".
    create table(:items, primary_key: [type: :binary_id]) do
      add :name, :text
      add :done, :boolean, default: false, null: false

      add :_deleted_at, :utc_datetime
      add :_snapmin, :integer, null: false
      add :_snapcur, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    execute """
            CREATE OR REPLACE TRIGGER phx_sync_snap_before_insert_update
            BEFORE INSERT OR UPDATE ON items
            FOR EACH ROW
            EXECUTE FUNCTION phx_sync_snap_columns();
            """,
            """
            DROP TRIGGER IF EXISTS phx_sync_snap_before_insert_update ON items;
            """

    execute "ALTER PUBLICATION phx_sync ADD TABLE items",
            "ALTER PUBLICATION phx_sync DROP TABLE items"
  end
end
