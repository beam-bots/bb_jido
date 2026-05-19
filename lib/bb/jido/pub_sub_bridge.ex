# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.PubSubBridge do
  @moduledoc """
  GenServer that bridges `BB.PubSub` messages into a Jido agent as signals.

  Subscribes to configured BB topics on behalf of a Jido agent process and
  forwards each `{:bb, source_path, %BB.Message{}}` delivery as a
  `Jido.Signal` via `Jido.AgentServer.cast/2`.

  ## Options

  - `:robot` — robot module to subscribe against (required).
  - `:agent` — pid or registered name of the Jido agent server that should
    receive the forwarded signals (required).
  - `:topics` — list of paths to subscribe to (default `[[:state_machine]]`).
    Each path is a list of atoms as accepted by `BB.PubSub.subscribe/3`.
  - `:message_types` — list of payload modules to filter on at subscription
    time (default `[]`, meaning no filter). Applied to every topic.
  - `:throttle_ms` — optional minimum interval between signals of the same
    type. Repeated signals arriving within the window are dropped. Defaults
    to no throttling.

  ## Filtering

  Topic and message-type filtering happen at the PubSub layer (cheap). The
  bridge additionally enforces an optional per-type throttle to limit signal
  volume for high-frequency topics (e.g. joint states at 100Hz).
  """

  use GenServer

  alias BB.Jido.Signal, as: SignalMap
  alias BB.Jido.Telemetry
  alias BB.Message

  require Logger

  @type option ::
          {:robot, module()}
          | {:agent, GenServer.server()}
          | {:topics, [[atom()]]}
          | {:message_types, [module()]}
          | {:throttle_ms, pos_integer()}
          | GenServer.option()

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {server_opts, init_opts} =
      Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @impl GenServer
  def init(opts) do
    robot = Keyword.fetch!(opts, :robot)
    agent = Keyword.fetch!(opts, :agent)
    topics = Keyword.get(opts, :topics, default_topics())
    message_types = Keyword.get(opts, :message_types, [])
    throttle_ms = Keyword.get(opts, :throttle_ms)

    case subscribe_all(robot, topics, message_types) do
      :ok ->
        {:ok,
         %{
           robot: robot,
           agent: agent,
           topics: topics,
           throttle_ms: throttle_ms,
           last_emitted: %{}
         }}

      {:error, reason} ->
        {:stop, {:subscribe_failed, reason}}
    end
  end

  @impl GenServer
  def handle_info({:bb, path, %Message{} = message}, state) do
    signal = SignalMap.from_pubsub(state.robot, path, message)

    case maybe_emit(signal, state) do
      {:emit, new_state} ->
        Telemetry.emit_signal(state.robot, signal.type)
        dispatch(state.agent, signal)
        {:noreply, new_state}

      {:drop, new_state} ->
        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp dispatch(agent, signal) do
    case Jido.AgentServer.cast(agent, signal) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("BB.Jido.PubSubBridge could not cast signal to agent: #{inspect(reason)}")
    end
  end

  defp maybe_emit(_signal, %{throttle_ms: nil} = state), do: {:emit, state}

  defp maybe_emit(signal, %{throttle_ms: throttle_ms} = state) do
    now = System.monotonic_time(:millisecond)
    last = Map.get(state.last_emitted, signal.type)

    if is_nil(last) or now - last >= throttle_ms do
      {:emit, %{state | last_emitted: Map.put(state.last_emitted, signal.type, now)}}
    else
      {:drop, state}
    end
  end

  defp subscribe_all(robot, topics, message_types) do
    opts = if message_types == [], do: [], else: [message_types: message_types]

    Enum.reduce_while(topics, :ok, fn topic, :ok ->
      case BB.PubSub.subscribe(robot, topic, opts) do
        {:ok, _pid} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {topic, reason}}}
      end
    end)
  end

  defp default_topics, do: [[:state_machine]]
end
