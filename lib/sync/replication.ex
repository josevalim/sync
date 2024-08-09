defmodule Sync.Replication do
  use Postgrex.ReplicationConnection

  require Logger

  # TODO: We should explicitly subscribe and send a connect message every time we connect
  # TODO: Allow the publications to be passed as parameters
  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if not is_atom(name) or name == nil do
      raise ArgumentError, "an atom :name is required when starting #{inspect(__MODULE__)}"
    end

    {endpoint, opts} = Keyword.pop!(opts, :endpoint)
    opts = Keyword.put_new(opts, :auto_reconnect, true)
    Postgrex.ReplicationConnection.start_link(__MODULE__, endpoint, opts)
  end

  @doc """
  Subscribe to events from the replication connection.

  This is useful to know whenever there is a reconnection,
  which should force clients to resync.
  """
  def subscribe(name) do
    Registry.register(Sync.Registry, name, [])
  end

  @doc """
  Wait for connection.

  This is typically used by boot to make sure the replication
  is running to avoid unecessary syncs. It accepts a maximum
  timeout.

  This function will exit if the server is not running.
  It returns `:ok` or `:timeout` otherwise.
  """
  def wait_for_connection!(name, timeout \\ 5000) do
    ref = :erlang.monitor(:process, name, alias: :reply_demonitor)
    send(name, {:wait_for_connection, ref})

    receive do
      :ok ->
        :ok

      {:DOWN, ^ref, _, _, reason} ->
        exit({reason, {__MODULE__, :wait_for_connection!, [name, timeout]}})
    after
      timeout -> :timeout
    end
  end

  @doc """
  Use to emulate a disconnection from the database.
  """
  def disconnect(name) do
    send(name, :disconnect)
  end

  ## Callbacks

  @impl true
  def init(endpoint) do
    state = %{
      endpoint: endpoint,
      relations: %{},
      # {:disconnected, []} | :connected | [operation]
      replication: {:disconnected, []}
    }

    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{replication: replication} = state) do
    waiting =
      case replication do
        {:disconnected, waiting} -> waiting
        _ -> []
      end

    {:noreply, %{state | replication: {:disconnected, waiting}}}
  end

  @impl true
  def handle_connect(state) do
    slot = random_slot_name()
    query = "CREATE_REPLICATION_SLOT #{slot} TEMPORARY LOGICAL pgoutput NOEXPORT_SNAPSHOT"
    {:query, query, state}
  end

  @impl true
  def handle_info({:wait_for_connection, ref}, state) do
    case state.replication do
      {:disconnected, waiting} ->
        {:noreply, %{state | replication: {:disconnected, [ref | waiting]}}}

      _ ->
        send(ref, :ok)
        {:noreply, state}
    end
  end

  def handle_info(:disconnect, _state) do
    {:disconnect, "user requested"}
  end

  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def handle_result([result], %{replication: {:disconnected, waiting}} = state) do
    %Postgrex.Result{
      command: :create,
      columns: ["slot_name", "consistent_point", "snapshot_name", "output_plugin"],
      rows: [[slot, _lsn, nil, "pgoutput"]]
    } = result

    for ref <- waiting do
      send(ref, :ok)
    end

    {:registered_name, name} = Process.info(self(), :registered_name)

    Registry.dispatch(Sync.Registry, name, fn data ->
      Enum.each(data, fn {pid, _} ->
        send(pid, {__MODULE__, %{message: :connect}})
      end)
    end)

    query =
      "START_REPLICATION SLOT #{slot} LOGICAL 0/0 (proto_version '2', publication_names 'phx_sync')"

    {:stream, query, [], %{state | replication: :connected}}
  end

  def handle_result(%Postgrex.Error{} = error, _state) do
    raise Exception.message(error)
  end

  @impl true
  # https://www.postgresql.org/docs/14/protocol-replication.html
  def handle_data(<<?w, _wal_start::64, _wal_end::64, _clock::64, rest::binary>>, state) do
    case rest do
      <<?B, _lsn::64, _ts::64, _xid::32>> when state.replication == :connected ->
        handle_begin(state)

      <<?C, _flags::8, _commit_lsn::64, lsn::64, _ts::64>> when is_list(state.replication) ->
        handle_commit(lsn, state)

      <<?I, oid::32, ?N, count::16, tuple_data::binary>> when is_list(state.replication) ->
        handle_tuple_data(:insert, oid, count, tuple_data, state)

      <<?U, oid::32, ?N, count::16, tuple_data::binary>> when is_list(state.replication) ->
        handle_tuple_data(:update, oid, count, tuple_data, state)

      <<?U, oid::32, _, _::binary>> when is_list(state.replication) ->
        %{^oid => {schema, table, _columns}} = state.relation

        Logger.error(
          "A primary key of a row has been changed or its replica identity has been set to full, " <>
            "those operations are not currently supported by sync on #{schema}.#{table}"
        )

        {:noreply, state}

      <<?R, oid::32, rest::binary>> ->
        handle_relation(oid, rest, state)

      _ ->
        {:noreply, state}
    end
  end

  def handle_data(<<?k, wal_end::64, _clock::64, reply>>, state) do
    messages =
      case reply do
        1 -> [<<?r, wal_end + 1::64, wal_end + 1::64, wal_end + 1::64, current_time()::64, 0>>]
        0 -> []
      end

    {:noreply, messages, state}
  end

  ## Decoding messages

  defp handle_begin(state) do
    {:noreply, %{state | replication: []}}
  end

  defp handle_relation(oid, rest, state) do
    [schema, rest] = :binary.split(rest, <<0>>)
    schema = if schema == "", do: "pg_catalog", else: schema
    [table, <<_replica_identity::8, count::16, rest::binary>>] = :binary.split(rest, <<0>>)
    columns = parse_columns(count, rest)
    state = put_in(state.relations[oid], {schema, table, columns})
    {:noreply, state}
  end

  defp handle_tuple_data(kind, oid, count, tuple_data, state) do
    {schema, table, columns} = Map.fetch!(state.relations, oid)
    data = parse_tuple_data(count, columns, tuple_data)
    operation = %{schema: schema, table: table, op: kind, data: Map.new(data)}
    {:noreply, update_in(state.replication, &[operation | &1])}
  end

  defp handle_commit(lsn, state) do
    # TODO: Encode this as binary data.
    # TODO: Potentially allow synchronizing a subset of the fields.
    # TODO: lsn can cause an overflow on the client, since JS integers are floats.
    # TODO: Broadcast will encode to JSON when fastlaning,
    #       this can be expensive if done directly in the replication process.
    #       We can probably partition this over several processes.
    # TODO: The broadcast should be per table and a commit can touch several
    #       tables. We need an efficient mechanism to filter these down and
    #       send to the client. Perhaps by using a custom Registry rather than
    #       PubSub, since it is all local anyway.
    state.endpoint.local_broadcast("todo:items", "commit", %{
      lsn: lsn,
      ops: Enum.reverse(state.replication)
    })

    {:noreply, %{state | replication: :connected}}
  end

  defp parse_tuple_data(0, [], <<>>), do: []

  defp parse_tuple_data(count, [{name, _oid, _modifier} | columns], data) do
    case data do
      <<?n, rest::binary>> ->
        [{name, nil} | parse_tuple_data(count - 1, columns, rest)]

      # TODO: We are using text for convenience, we must set binary on the protocol
      <<?t, size::32, value::binary-size(size), rest::binary>> ->
        [{name, value} | parse_tuple_data(count - 1, columns, rest)]

      <<?b, _rest::binary>> ->
        raise "binary values not supported by sync"

      <<?u, rest::binary>> ->
        parse_tuple_data(count - 1, columns, rest)
    end
  end

  defp parse_columns(0, <<>>), do: []

  defp parse_columns(count, <<_flags, rest::binary>>) do
    [name, <<oid::32, modifier::32, rest::binary>>] = :binary.split(rest, <<0>>)
    [{name, oid, modifier} | parse_columns(count - 1, rest)]
  end

  ## Helpers

  @epoch DateTime.to_unix(~U[2000-01-01 00:00:00Z], :microsecond)
  defp current_time(), do: System.os_time(:microsecond) - @epoch

  defp random_slot_name do
    "phx_sync_" <> Base.encode32(:crypto.strong_rand_bytes(5), case: :lower)
  end
end
