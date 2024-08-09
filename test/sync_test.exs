defmodule SyncTest do
  # We don't use Sync.DataCase because want to automatically manage connections.
  use ExUnit.Case

  alias Sync.Repo
  alias Sync.Todo.Item

  import Ecto.Changeset

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    Repo.delete_all("items")
    :ok
  end

  describe "items" do
    test "sets _snapmin and _snapcur on insertion" do
      item = Repo.insert!(%Item{name: "study"})
      assert is_integer(item._snapmin)
      assert is_integer(item._snapcur)
    end

    test "holds _snapmin and _snapcur apart on long running transactions" do
      parent = self()

      task =
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

          Repo.transaction(fn ->
            Repo.insert!(%Item{name: "blocking"})
            send(parent, :ready)
            assert_receive :done
          end)
        end)

      assert_receive :ready

      item = Repo.insert!(%Item{name: "study"})
      assert is_integer(item._snapmin)
      assert is_integer(item._snapcur)
      assert item._snapmin < item._snapcur

      send(task.pid, :done)
      assert Task.await(task)
    end

    test "updates _snapmin and _snapcur on update" do
      item = Repo.insert!(%Item{name: "study"})
      assert is_integer(item._snapmin)
      assert is_integer(item._snapcur)

      updated_item = Repo.update!(change(item, name: "study harder!"))
      assert item._snapmin != updated_item._snapmin
      assert item._snapcur != updated_item._snapcur

      # Add pg_lsn type to Postgrex
      # %{rows: [[lsn]]} = Repo.query!("SELECT pg_current_wal_lsn()::text")
      # [high_hex, low_hex] = :binary.split(lsn, "/")
      # high_int = String.to_integer(high_hex, 16)
      # low_int = String.to_integer(low_hex, 16)
      # IO.inspect(Bitwise.bsl(high_int, 32) + low_int)
    end

    test "broadcasts insertions and updates" do
      SyncWeb.Endpoint.subscribe("todo:items")

      {:ok, id} =
        Repo.transaction(fn ->
          item = Repo.insert!(%Item{name: "study"})
          item = Repo.update!(change(item, name: "study harder!"))
          item.id
        end)

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: "todo:items",
                       event: "commit",
                       payload: %{
                         ops: [
                           %{
                             op: :insert,
                             table: "items",
                             schema: "public",
                             data: %{"id" => ^id, "name" => "study"}
                           },
                           %{
                             op: :update,
                             table: "items",
                             schema: "public",
                             data: %{"id" => ^id, "name" => "study harder!"}
                           }
                         ],
                         lsn: lsn
                       }
                     }
                     when is_integer(lsn)
    end

    test "broadcasts with TOAST" do
      SyncWeb.Endpoint.subscribe("todo:items")
      name = String.duplicate("a", 1_000_000)

      {:ok, id} =
        Repo.transaction(fn ->
          item = Repo.insert!(%Item{name: name})
          item = Repo.update!(change(item, done: true))
          item.id
        end)

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: "todo:items",
                       event: "commit",
                       payload: %{
                         ops: [
                           %{
                             op: :insert,
                             table: "items",
                             schema: "public",
                             data: %{"id" => ^id, "name" => ^name}
                           },
                           %{
                             op: :update,
                             table: "items",
                             schema: "public",
                             data: %{"id" => ^id}
                           }
                         ],
                         lsn: lsn
                       }
                     }
                     when is_integer(lsn)
    end
  end
end
