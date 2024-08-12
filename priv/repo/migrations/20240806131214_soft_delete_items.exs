defmodule Sync.Repo.Migrations.SoftDeleteItems do
  use Ecto.Migration

  # Source: https://evilmartians.com/chronicles/soft-deletion-with-postgresql-but-with-logic-on-the-database
  # We want to make this part of the `syncify` operation.
  def change do
    # TODO: We should allow users to configure which fields are pruned on soft deletion.
    # TODO: We need to do it in a way that cascades foreign keys.
    #       Perhaps by doing a query that finds all foreign keys relationships?
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
