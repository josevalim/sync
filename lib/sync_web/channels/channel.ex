defmodule SyncWeb.Channel do
  use SyncWeb, :channel

  alias Sync.Repo
  import Ecto.Query

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
  # and below the current database snapmin, as written below.
  # We return the latest "snapmin" to the client. The "snapmin"
  # (and the soon to be described "lsn") are tracked per resource,
  # but since this proof of concept only has a single resource
  # (the "items" table), we don't need to worry about it right
  # now.
  #
  # The sync also returns a "lsn". While we are syncing, we may
  # receive replication "commit" events. However, those need to
  # be buffered until the "commit" event has a "lsn" that matches
  # or suparpasses the returned sync "lsn". Then we can merge all
  # replication commits into the actual data and store it locally.
  # As we merge the replication events, each row has a "_snapmin"
  # column. We should update the resource snapmin in the client
  # if the row "_snapmin" is bigger than the client one.
  #
  # TODO: Do we want to allow multiple resources to be synced in
  # parallel and then emit data directly to the socket?
  # TODO: _snapmin and lsn can overflow on the client because JS
  # ints are actually float. We need to handle this carefully
  # in the future.
  # TODO: We probably want to send data as binaries and
  # have the client parse it, mirroring whatever happens
  # in the replication layer.
  @impl true
  def handle_in("sync", %{"snapmin" => client_snapmin}, socket) do
    # Subscribe before any query
    socket = update_subscriptions("sync:todos:items", socket)

    {:ok, payload} =
      Repo.transaction(fn ->
        %{rows: [[server_snapmin]]} =
          Repo.query!("SELECT pg_snapshot_xmin(pg_current_snapshot())")

        data =
          Repo.all(
            from s in Sync.Todo.Item,
              where: s._snapmin >= ^client_snapmin and s._snapmin < ^server_snapmin
          )

        %{rows: [[lsn]]} = Repo.query!("SELECT pg_current_wal_lsn()::text")
        {:ok, lsn} = Postgrex.ReplicationConnection.decode_lsn(lsn)
        %{snapmin: server_snapmin, data: [["items", data]], lsn: lsn}
      end)

    {:reply, {:ok, payload}, socket}
  end

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
