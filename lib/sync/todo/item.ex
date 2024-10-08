defmodule Sync.Todo.Item do
  use Ecto.Schema
  import Ecto.Changeset

  # TODO: Introduce sync_schema that will define the snapshot columns and the scope
  # TODO: Figure out schema evolution
  @primary_key {:id, :binary_id, autogenerate: true}

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :done,
             :_deleted_at,
             :_snapmin,
             :_snapcur,
             :inserted_at,
             :updated_at
           ]}
  schema "visible_items" do
    field :name, :string
    field :done, :boolean, default: false

    # TODO: Use writable: :never on Ecto v3.12+
    # TODO: read_after_writes does not work with soft deletes on Postgres,
    #       we need to address this in Ecto and add it later
    field :_deleted_at, :utc_datetime, read_after_writes: true
    field :_snapmin, :integer, read_after_writes: true
    field :_snapcur, :integer, read_after_writes: true

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :done])
    |> validate_required([:name, :done])
  end
end
