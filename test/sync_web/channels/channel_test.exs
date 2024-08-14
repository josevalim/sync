defmodule SyncWeb.ChannelChannelTest do
  use SyncWeb.ChannelCase

  @moduletag cleanup: ["items"]

  setup do
    {:ok, _, socket} =
      socket(SyncWeb.Socket)
      |> subscribe_and_join(SyncWeb.Channel, "sync:todos")

    %{socket: socket}
  end

  test "sync receives latest data", %{socket: socket} do
    ref = push(socket, "sync", %{"snapmin" => "0"})
    assert_reply ref, :ok, %{data: [["items", []]], lsn: lsn, snapmin: snapmin}
    assert is_integer(lsn) and is_integer(snapmin)

    %{id: id} = Sync.Repo.insert!(%Sync.Todo.Item{name: "study"})
    ref = push(socket, "sync", %{"snapmin" => "0"})

    assert_reply ref, :ok, %{
      data: [["items", [%Sync.Todo.Item{id: ^id}]]],
      lsn: lsn,
      snapmin: snapmin
    }

    assert is_integer(lsn) and is_integer(snapmin)

    ref = push(socket, "sync", %{"snapmin" => snapmin})
    assert_reply ref, :ok, %{data: [["items", []]], lsn: lsn, snapmin: snapmin}
    assert is_integer(lsn) and is_integer(snapmin)
  end

  test "sync fetches soft-deleted data with snapmin", %{socket: socket} do
    %{id: id} = item = Sync.Repo.insert!(%Sync.Todo.Item{name: "study"})
    Sync.Repo.delete!(item, allow_stale: true)

    ref = push(socket, "sync", %{"snapmin" => "0"})

    assert_reply ref, :ok, %{
      data: [["items", [%Sync.Todo.Item{id: ^id, _deleted_at: %DateTime{}}]]],
      lsn: lsn,
      snapmin: snapmin
    }

    assert is_integer(lsn) and is_integer(snapmin)
  end

  test "sync does not fetch soft-deleted data without", %{socket: socket} do
    item = Sync.Repo.insert!(%Sync.Todo.Item{name: "study"})
    Sync.Repo.delete!(item, allow_stale: true)

    ref = push(socket, "sync", %{})
    assert_reply ref, :ok, %{data: [["items", []]], lsn: lsn, snapmin: snapmin}
    assert is_integer(lsn) and is_integer(snapmin)
  end
end
