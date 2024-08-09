defmodule SyncWeb.ChannelChannelTest do
  use SyncWeb.ChannelCase

  @moduletag cleanup: ["items"]

  setup do
    {:ok, _, socket} =
      socket(SyncWeb.Socket)
      |> subscribe_and_join(SyncWeb.Channel, "todo:sync")

    %{socket: socket}
  end

  test "sync receives latest data", %{socket: socket} do
    ref = push(socket, "sync", %{"snapmin" => "0"})
    assert_reply ref, :ok, %{data: [], lsn: lsn, snapmin: snapmin}
    assert is_integer(lsn) and is_integer(snapmin)

    %{id: id} = Sync.Repo.insert!(%Sync.Todo.Item{name: "study"})
    ref = push(socket, "sync", %{"snapmin" => "0"})
    assert_reply ref, :ok, %{data: [%Sync.Todo.Item{id: ^id}], lsn: lsn, snapmin: snapmin}
    assert is_integer(lsn) and is_integer(snapmin)

    ref = push(socket, "sync", %{"snapmin" => snapmin})
    assert_reply ref, :ok, %{data: [], lsn: lsn, snapmin: snapmin}
    assert is_integer(lsn) and is_integer(snapmin)
  end

  test "sync does not fetch soft-deleted data", %{socket: socket} do
    Sync.Repo.insert!(%Sync.Todo.Item{
      name: "study",
      _deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    ref = push(socket, "sync", %{"snapmin" => "0"})
    assert_reply ref, :ok, %{data: [], lsn: lsn, snapmin: snapmin}
    assert is_integer(lsn) and is_integer(snapmin)
  end
end
