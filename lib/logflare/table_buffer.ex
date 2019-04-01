defmodule Logflare.TableBuffer do
  use GenServer

  require Logger

  def start_link(website_table) do
    GenServer.start_link(
      __MODULE__,
      %{
        source: website_table,
        buffer: :queue.new(),
        read_receipts: :queue.new()
      },
      name: name(website_table)
    )
  end

  def init(state) do
    Logger.info("Table buffer started: #{state.source}")
    {:ok, state}
  end

  def push(website_table, event) do
    GenServer.cast(name(website_table), {:push, event})
  end

  def pop(website_table) do
    GenServer.call(name(website_table), :pop)
  end

  def ack(website_table) do
    GenServer.call(name(website_table), :ack)
  end

  def handle_cast({:push, event}, state) do
    new_buffer = :queue.in(event, state.buffer)

    new_state = %{state | buffer: new_buffer}
    {:noreply, new_state}
  end

  def handle_call(:pop, _from, state) do
    case :queue.is_empty(state.buffer) do
      true ->
        {:reply, :empty, state}

      false ->
        {event, new_buffer} = :queue.out(state.buffer)
        new_read_receipts = :queue.in(event, state.read_receipts)

        new_state = %{state | buffer: new_buffer, read_receipts: new_read_receipts}
        {:reply, event, new_state}
    end
  end

  def handle_call(:ack, _from, state) do
    case :queue.is_empty(state.read_receipts) do
      true ->
        {:reply, :empty, state}

      false ->
        {event, new_read_receipts} = :queue.out(state.read_receipts)

        new_state = %{state | read_receipts: new_read_receipts}
        {:reply, event, new_state}
    end
  end

  defp name(website_table) do
    String.to_atom("#{website_table}" <> "-buffer")
  end
end
