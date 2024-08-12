defmodule SyncTest do
  # We don't use Sync.DataCase because want to automatically manage connections.
  use Sync.DataCase
  alias Sync.Todo.Item

  @moduletag cleanup: ["items"]

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
    end

    test "soft deletion" do
      %{id: id} = item = Repo.insert!(%Item{name: "study"})
      Sync.Repo.delete!(item, allow_stale: true)

      assert [] = Repo.all(Item)
      assert [%{id: ^id}] = Repo.all({"items", Item})
    end

    test "disabled soft deletion" do
      item = Repo.insert!(%Item{name: "study"})

      # TODO: Perhaps encapsulate this into a repository operation?
      Repo.transaction(fn ->
        Repo.query!("ALTER TABLE items DISABLE RULE phx_sync_soft_deletion")
        Sync.Repo.delete!(item)
        Repo.query!("ALTER TABLE items ENABLE RULE phx_sync_soft_deletion")
      end)

      assert [] = Repo.all(Item)
      assert [] = Repo.all({"items", Item})
    end
  end

  describe "replication" do
    test "sends a message on reconnection" do
      Sync.Replication.subscribe(Sync.Replication)
      Sync.Replication.disconnect(Sync.Replication)
      assert_receive {Sync.Replication, %{message: :connect}}
    end

    test "broadcasts insertions and updates" do
      SyncWeb.Endpoint.subscribe("sync:todos:items")

      {:ok, id} =
        Repo.transaction(fn ->
          item = Repo.insert!(%Item{name: "study"})
          item = Repo.update!(change(item, name: "study harder!"))
          item.id
        end)

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: "sync:todos:items",
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
      SyncWeb.Endpoint.subscribe("sync:todos:items")
      name = String.duplicate("a", 1_000_000)

      {:ok, id} =
        Repo.transaction(fn ->
          item = Repo.insert!(%Item{name: name})
          item = Repo.update!(change(item, done: true))
          item.id
        end)

      assert_receive %Phoenix.Socket.Broadcast{
                       topic: "sync:todos:items",
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
