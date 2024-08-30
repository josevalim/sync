defmodule Sync.Repo.Migrations.SoftDeleteItems do
  use Ecto.Migration

  def change do
    # TODO: Use a separate table for deletions, for each table, instead of deleted_at columns
    # See https://brandur.org/fragments/deleted-record-insert.
    # TODO: We want to make this part of the `syncify` operation.
    execute """
            CREATE OR REPLACE RULE phx_sync_soft_deletion AS ON DELETE TO items
            DO INSTEAD UPDATE items SET _deleted_at = NOW() WHERE id = OLD.id AND _deleted_at IS NULL RETURNING OLD.*;
            """,
            """
            DROP RULE IF EXISTS phx_sync_soft_deletion ON items;
            """

    execute "CREATE OR REPLACE VIEW visible_items AS SELECT * FROM items WHERE _deleted_at IS NULL",
            "DROP VIEW IF EXISTS visible_items"
  end
end
