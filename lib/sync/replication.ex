defmodule Sync.Replication do
  use Postgrex.ReplicationConnection

  # TODO: Allow the publications to be passed as parameters
  def start_link(opts) do
    {pubsub, opts} = Keyword.pop!(opts, :pubsub)
    opts = Keyword.put_new(opts, :auto_reconnect, true)
    Postgrex.ReplicationConnection.start_link(__MODULE__, pubsub, opts)
  end

  defp random_slot_name do
    "phx_sync_" <> Base.encode32(:crypto.strong_rand_bytes(5), case: :lower)
  end

  @impl true
  def init(pubsub) do
    {:ok, %{step: :disconnected, pubsub: pubsub, slot: nil}}
  end

  @impl true
  def handle_connect(state) do
    slot = random_slot_name()
    query = "CREATE_REPLICATION_SLOT #{slot} TEMPORARY LOGICAL pgoutput NOEXPORT_SNAPSHOT"
    {:query, query, %{state | step: :create_slot, slot: slot}}
  end

  @impl true
  def handle_result(results, %{step: :create_slot} = state) when is_list(results) do
    query =
      "START_REPLICATION SLOT #{state.slot} LOGICAL 0/0 (proto_version '1', publication_names 'phx_sync')"

    {:stream, query, [], %{state | step: :streaming}}
  end

  @impl true
  # https://www.postgresql.org/docs/14/protocol-replication.html
  def handle_data(<<?w, _wal_start::64, _wal_end::64, _clock::64, rest::binary>>, state) do
    IO.inspect(rest)
    {:noreply, state}
  end

  def handle_data(<<?k, wal_end::64, _clock::64, reply>>, state) do
    messages =
      case reply do
        1 -> [<<?r, wal_end + 1::64, wal_end + 1::64, wal_end + 1::64, current_time()::64, 0>>]
        0 -> []
      end

    {:noreply, messages, state}
  end

  @epoch DateTime.to_unix(~U[2000-01-01 00:00:00Z], :microsecond)
  defp current_time(), do: System.os_time(:microsecond) - @epoch
end
