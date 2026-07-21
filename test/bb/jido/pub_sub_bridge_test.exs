# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.PubSubBridgeTest do
  use ExUnit.Case, async: false

  alias BB.Jido.PubSubBridge
  alias BB.Jido.TestRobot
  alias BB.Message
  alias BB.StateMachine.Transition

  defmodule FakeAgent do
    @moduledoc false
    use GenServer

    def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)

    @impl true
    def init(test_pid), do: {:ok, test_pid}

    # The bridge dispatches via Jido.AgentServer.cast/2, which ultimately
    # sends a `{:"$gen_cast", {:signal, signal}}` to the agent process.
    @impl true
    def handle_cast({:signal, signal}, test_pid) do
      send(test_pid, {:agent_received, signal})
      {:noreply, test_pid}
    end
  end

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    {:ok, agent} = FakeAgent.start_link(self())
    {:ok, agent: agent}
  end

  test "forwards state-machine transitions to the agent as signals", %{agent: agent} do
    {:ok, _bridge} =
      PubSubBridge.start_link(
        robot: TestRobot,
        agent: agent,
        topics: [[:state_machine]]
      )

    # Arming runs as a command, so the robot emits several state-machine
    # transitions; we only require that the :armed one is forwarded as a
    # signal, regardless of how the intermediate transitions interleave.
    {:ok, cmd} = TestRobot.arm(%{})
    {:ok, :armed, _} = BB.Command.await(cmd)

    assert_armed_signal_received()
  end

  defp assert_armed_signal_received do
    assert_receive {:agent_received, signal}, 1_000
    assert signal.type == "bb.state.transition"

    case signal.data.message do
      %Message{payload: %Transition{to: :armed}} -> :ok
      %Message{payload: %Transition{}} -> assert_armed_signal_received()
    end
  end

  test "throttling drops repeat signals of the same type within the window", %{agent: agent} do
    {:ok, bridge} =
      PubSubBridge.start_link(
        robot: TestRobot,
        agent: agent,
        topics: [[:state_machine]],
        throttle_ms: 60_000
      )

    msg = %Message{
      monotonic_time: 0,
      wall_time: 0,
      node: node(),
      frame_id: :sensor,
      payload: %{__struct__: FakeSensorReading, value: 1}
    }

    send(bridge, {:bb, [:sensor, :fake], msg})
    assert_receive {:agent_received, %{type: "bb.pubsub.sensor.fake"}}, 500

    send(bridge, {:bb, [:sensor, :fake], msg})
    refute_receive {:agent_received, _}, 200
  end

  test "safety transitions bypass the throttle so a disarm is never dropped", %{agent: agent} do
    {:ok, bridge} =
      PubSubBridge.start_link(
        robot: TestRobot,
        agent: agent,
        topics: [[:state_machine]],
        throttle_ms: 60_000
      )

    transition = fn from, to ->
      %Message{
        monotonic_time: 0,
        wall_time: 0,
        node: node(),
        frame_id: :state_machine,
        payload: %Transition{from: from, to: to}
      }
    end

    send(bridge, {:bb, [:state_machine], transition.(:disarmed, :armed)})

    assert_receive {:agent_received,
                    %{data: %{message: %Message{payload: %Transition{to: :armed}}}}},
                   500

    send(bridge, {:bb, [:state_machine], transition.(:armed, :disarmed)})

    assert_receive {:agent_received,
                    %{data: %{message: %Message{payload: %Transition{to: :disarmed}}}}},
                   500
  end
end
