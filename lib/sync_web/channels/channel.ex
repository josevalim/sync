defmodule SyncWeb.Channel do
  use SyncWeb, :channel

  alias Sync.Repo
  import Ecto.Query

  @impl true
  def join("sync:todos", _payload, socket) do
    Sync.Replication.subscribe(Sync.Replication)
    {:ok, assign(socket, :subscriptions, MapSet.new())}
  end

  # This message is received when we lose connection to PostgreSQL,
  # which means we may have missed replication events. Right now,
  # this will force a resync but in the future we should just rather
  # mark all colletions as stale, so they are force synced as they
  # are used on the client.
  @impl true
  def handle_info({Sync.Replication, %{message: :connect}}, socket) do
    {:noreply, push(socket, "resync", %{})}
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
  def handle_in("sync", payload, socket) do
    # Subscribe before any query
    # TODO: This should return the connection LSN right after the
    # subscription. The replication can keep the current LSN in a
    # counter, and store it in the Registry meta key.
    socket = update_subscriptions("sync:todos:items", socket)

    {:ok, payload} =
      Repo.transaction(fn ->
        %{rows: [[server_snapmin]]} =
          Repo.query!("SELECT pg_snapshot_xmin(pg_current_snapshot())")

        query =
          if client_snapmin = Map.get(payload, "snapmin") do
            # TODO: This also returns deleted data, because we need to tell the client
            # if a particular row was removed. In the future, we probably want to return
            # only the IDs and not the whole record.
            from s in {"items", Sync.Todo.Item}, where: s._snapmin >= ^client_snapmin
          else
            from s in {"items", Sync.Todo.Item}, where: is_nil(s._deleted_at)
          end

        data = Repo.all(query)
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
  #
  # TODO: Writes do not need to happen on the channel. It could
  # happen over HTTP and it could have benefits too: writes need
  # to go somewhere close to the primary, channels can be on the
  # edge, close to replicas.
  @impl true
  def handle_in("write", %{"ops" => ops}, socket) do
    reply =
      Repo.transaction(fn -> Enum.reduce_while(ops, {:ok, %{}}, &handle_write/2) end)

    case reply do
      {:ok, {:ok, _}} -> {:reply, :ok, socket}
      {:ok, {:halt, error}} -> {:reply, {:error, error}, socket}
      # TODO handle rollback with meaningful client error
      {:error, _rollback} -> {:reply, {:error, %{op: hd(ops), errors: []}}, socket}
    end
  end

  defp handle_write([_op_id, "insert", "items", data] = op, acc) do
    %{"id" => id} = data

    case Repo.insert(Sync.Todo.Item.changeset(%Sync.Todo.Item{id: id}, data)) do
      {:ok, _} -> {:cont, acc}
      {:error, changeset} -> {:halt, {:error, %{op: op, errors: changeset.errors}}}
    end
  end

  defp handle_write([_op_id, "update", "items", %{"id" => id} = data] = op, acc) do
    # TODO conflict resolution – someone raced out update with a delete,
    case Repo.get(Sync.Todo.Item, id) do
      nil ->
        {:cont, acc}

      %Sync.Todo.Item{} = todo ->
        case Repo.update(Sync.Todo.Item.changeset(todo, data)) do
          {:ok, _} -> {:cont, acc}
          {:error, changeset} -> {:halt, {:error, %{op: op, errors: changeset.errors}}}
        end
    end
  end

  defp handle_write([_op_id, "delete", "items", id], acc) do
    {_, _} = Repo.delete_all(from i in Sync.Todo.Item, where: i.id == ^id)
    {:cont, acc}
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
