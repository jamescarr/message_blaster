defmodule MessageBlaster.Producer do
  @moduledoc """
  Producer that emits JSON messages at a configured rate and publishes them.
  Supports generating from a map of Avro schemas (full_name => schema).
  """
  use GenServer
  require Logger

  alias MessageBlaster.Publisher.SQSPublisher
  alias MessageBlaster.AvroGenerator

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_producing(opts \\ []) do
    GenServer.call(__MODULE__, {:start, opts})
  end

  def stop_producing do
    GenServer.call(__MODULE__, :stop)
  end

  def set_rate(rate) when is_integer(rate) and rate > 0 do
    GenServer.call(__MODULE__, {:set_rate, rate})
  end

  @impl true
  def init(_opts) do
    state = %{
      rate: get_in(Application.get_env(:message_blaster, :producer), [:default_rate]) || 20,
      timer_ref: nil,
      running: false,
      schemas: %{},
      schema_cycle: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start, opts}, _from, state) do
    rate = Keyword.get(opts, :rate, state.rate)
    schemas = Keyword.get(opts, :schemas, %{})
    schema_cycle = Map.keys(schemas)

    interval_ms = max(div(1000, max(rate, 1)), 1)

    if state.running do
      {:reply, :ok, state}
    else
      Logger.info("Producer starting at ~#{rate} msg/s per schema (#{interval_ms}ms interval)")
      ref = Process.send_after(self(), :tick, interval_ms)
      {:reply, :ok, %{state | rate: rate, timer_ref: ref, running: true, schemas: schemas, schema_cycle: schema_cycle}}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    Logger.info("Producer stopped")
    {:reply, :ok, %{state | timer_ref: nil, running: false}}
  end

  @impl true
  def handle_call({:set_rate, rate}, _from, state) do
    interval_ms = max(div(1000, max(rate, 1)), 1)
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    Logger.info("Producer rate updated to ~#{rate} msg/s per schema (#{interval_ms}ms)")
    ref = if state.running, do: Process.send_after(self(), :tick, interval_ms), else: nil
    {:reply, :ok, %{state | rate: rate, timer_ref: ref}}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = send_batch(state)
    interval_ms = max(div(1000, max(new_state.rate, 1)), 1)
    ref = Process.send_after(self(), :tick, interval_ms)
    {:noreply, %{new_state | timer_ref: ref}}
  end

  defp send_batch(%{schemas: schemas} = state) when map_size(schemas) == 0 do
    # Fallback: generate generic payload
    body = generic_random_json()
    publish(body, state)
    state
  end
  defp send_batch(%{schemas: schemas, schema_cycle: []} = state) do
    # reset cycle then send
    state
    |> Map.put(:schema_cycle, Map.keys(schemas))
    |> send_batch()
  end
  defp send_batch(%{schemas: schemas, schema_cycle: [schema_name | rest]} = state) do
    schema = Map.fetch!(schemas, schema_name)
    payload = AvroGenerator.generate(schema)
    body = Jason.encode!(payload)
    publish(body, state)
    %{state | schema_cycle: rest}
  end

  defp publish(body, state) do
    json = if is_binary(body), do: body, else: Jason.encode!(body)
    case SQSPublisher.send_message(json) do
      :ok ->
        :telemetry.execute([
          :message_blaster, :producer, :sent
        ], %{}, %{json: json, rate: state.rate, schemas: Map.keys(state.schemas)})
        :ok
      {:error, _} -> :ok
    end
  end

  defp generic_random_json do
    %{
      id: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
      value: Float.round(:rand.uniform() * 1000, 3),
      sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
end
