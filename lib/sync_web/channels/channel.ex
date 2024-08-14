defmodule SyncWeb.Channel do
  use SyncWeb, :channel

  alias Sync.Repo
  import Ecto.Query

  # TODO: Implement {Sync.Replication, %{message: :connect}}
  # event by asking the client to synchronize again.

  @impl true
  def join("sync:todos", _payload, socket) do
    {:ok, assign(socket, :subscriptions, MapSet.new())}
  end

  # The sync happens per table/view. This proof of concept
  # only has a single table, so we don't need to worry about
  # it for now.
  #
  # In order to sync, we need to receive the "snapmin" from
  # the client. The query we perform must be above the "snapmin"
  # and below the current database snapmin, as implemented below.
  # We return the latest "snapmin" to the client. The "snapmin"
  # (and the soon to be described "lsn") are tracked per resource,
  # but since this proof of concept only has a single resource
  # (the "items" table), we don't need to worry about it right
  # now.
  #
  # The sync also returns a "lsn". While we are syncing, we may
  # receive replication "commit" events. However, those need to
  # be buffered until the "commit" event has a "lsn" that matches
  # or suparpasses the returned sync "lsn". Only then we can merge
  # the sync data and all replication commits into the actual
  # client storage. This will give us snapshot isolation/transactional
  # consistency on the client. As we merge these (and future) replication
  # events, each row has a "_snapmin" column, and we should update
  # the resource snapmin in the client if the row "_snapmin" is
  # bigger than the client one.
  #
  # TODO: Allow multiple resources to be synced in
  # parallel and then emit data directly to the socket
  # TODO: _snapmin and lsn can overflow on the client because JS
  # ints are actually float. We need to handle this carefully
  # in the future.
  # TODO: We probably want to send data as binaries and
  # have the client parse it, mirroring whatever happens
  # in the replication layer.
  @impl true
  def handle_in("sync", %{"snapmin" => client_snapmin}, socket) do
    # Subscribe before any query
    # TODO: This should return the connection LSN right after the
    # subscription. The replication can keep the current LSN in a
    # counter, and store it in the Registry meta key.
    socket = update_subscriptions("sync:todos:items", socket)

    {:ok, payload} =
      Repo.transaction(fn ->
        %{rows: [[server_snapmin]]} =
          Repo.query!("SELECT pg_snapshot_xmin(pg_current_snapshot())")

        # TODO: This also returns deleted data, because we need to tell the client
        # if a particular row was removed. In the future, we probably want to return
        # only the IDs and not the whole record.
        data =
          Repo.all(from s in {"items", Sync.Todo.Item}, where: s._snapmin >= ^client_snapmin)

        %{rows: [[lsn]]} = Repo.query!("SELECT pg_current_wal_lsn()")
        %{snapmin: server_snapmin, data: [["items", data]], lsn: lsn}
      end)

    {:reply, {:ok, payload}, socket}
  end

  # For writes, the client has two storages: the sync storage and
  # the transaction storage. The sync storage only has the data
  # received through sync and replication layer. Whenever the client
  # wants to change data, it goes to the replication store first.
  # The in-memory data is the result of applying all transactions
  # in the transaction storage to the sync storage. Whenever we
  # receive a replication event, we discard the in-memory data,
  # update the sync storage, and apply the transactions on top.
  # Of course, there are several ways to optimize this as to not
  # recompute all data all over again all the time.
  #
  # TODO: IndexedDB is shared across tabs. It is necessary to
  # provide some mechanism to enable cross tab support.
  @impl true
  def handle_in("write", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  defp update_subscriptions(topic, socket) do
    subscriptions = socket.assigns.subscriptions

    if "sync:todos:items" in subscriptions do
      socket
    else
      # TODO: We should replace the usage of endpoint in SyncWeb.Replication
      # by a Registry with our own dispatching logic anyway.
      socket.endpoint.subscribe(topic,
        metadata: {:fastlane, socket.transport_pid, socket.serializer, []}
      )

      assign(socket, :subscriptions, MapSet.put(subscriptions, topic))
    end
  end
end
