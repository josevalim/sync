defmodule Sync.Todo.Item do
  use Ecto.Schema
  import Ecto.Changeset

  # TODO: Introduce sync_schema that will define the snapshot columns and the scope
  # TODO: Figure out schema evolution
  schema "items" do
    field :name, :string
    field :done, :boolean, default: false

    # TODO: Use writeable: :never on Ecto v3.12+
    field :_snapmin, :integer, read_after_writes: true
    field :_snapcur, :integer, read_after_writes: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name, :done])
    |> validate_required([:name, :done])
  end
end
