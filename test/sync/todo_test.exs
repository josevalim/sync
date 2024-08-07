defmodule Sync.TodoTest do
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
    end
  end
end
