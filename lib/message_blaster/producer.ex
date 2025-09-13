defmodule MessageBlaster.Producer do
  @moduledoc """
  Minimal producer that emits random JSON messages at a configured rate
  and publishes them via the configured publisher (direct SQS mode).
  """
  use GenServer
  require Logger

  alias MessageBlaster.Publisher.SQSPublisher

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
      running: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start, opts}, _from, state) do
    rate = Keyword.get(opts, :rate, state.rate)
    interval_ms = max(div(1000, max(rate, 1)), 1)

    if state.running do
      {:reply, :ok, state}
    else
      Logger.info("Producer starting at ~#{rate} msg/s (#{interval_ms}ms)")
      ref = Process.send_after(self(), :tick, interval_ms)
      {:reply, :ok, %{state | rate: rate, timer_ref: ref, running: true}}
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
    Logger.info("Producer rate updated to ~#{rate} msg/s (#{interval_ms}ms)")
    ref = if state.running, do: Process.send_after(self(), :tick, interval_ms), else: nil
    {:reply, :ok, %{state | rate: rate, timer_ref: ref}}
  end

  @impl true
  def handle_info(:tick, state) do
    send_one()
    interval_ms = max(div(1000, max(state.rate, 1)), 1)
    ref = Process.send_after(self(), :tick, interval_ms)
    {:noreply, %{state | timer_ref: ref}}
  end

  defp send_one do
    body = random_pokemon_json()
    case SQSPublisher.send_message(body) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end

  # Very simple JSON payload generator (placeholder for Avro-based gen)
  defp random_pokemon_json do
    names = ~w(Pikachu Charizard Blastoise Venusaur Alakazam Gengar Dragonite Mewtwo Lugia Ho-oh)
    types = ~w(Fire Water Grass Electric Psychic Fighting Dark Steel Dragon Fairy Normal)

    payload = %{
      id: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
      name: Enum.random(names),
      type: Enum.random(types),
      hp: Enum.random(60..300),
      value_usd: Float.round(:rand.uniform() * 5000, 2),
      trend: Enum.random(["rising", "falling", "stable"]),
      sent_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Jason.encode!(payload)
  end
end
