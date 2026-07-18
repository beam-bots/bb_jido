# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Plugin.RobotIntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias BB.Jido.TestRobot

  defmodule TestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "bb_jido_robot_integration_agent",
      plugins: [{BB.Jido.Plugin.Robot, %{robot: BB.Jido.TestRobot}}]
  end

  @jido_instance __MODULE__.JidoInstance

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    start_supervised!({Jido, name: @jido_instance})
    agent = start_supervised!({Jido.AgentServer, agent: TestAgent, jido: @jido_instance})
    await_bridge_started(agent)
    {:ok, agent: agent}
  end

  test "bridged safety transitions update the cached safety state without routing errors",
       %{agent: agent} do
    log =
      capture_log(fn ->
        {:ok, cmd} = TestRobot.arm(%{})
        {:ok, :armed, _} = BB.Command.await(cmd)

        await_agent_state(agent, fn state -> state.robot.safety_state == :armed end)
      end)

    refute log =~ "No route for signal"
  end

  test "routed command results merge into agent state without clobbering the plugin slice",
       %{agent: agent} do
    {:ok, cmd} = TestRobot.arm(%{})
    {:ok, :armed, _} = BB.Command.await(cmd)

    signal =
      Jido.Signal.new!("bb.command.execute", %{
        robot: TestRobot,
        command: :test_succeed,
        goal: %{value: :hello}
      })

    :ok = Jido.AgentServer.cast(agent, signal)

    await_agent_state(agent, fn state -> state[:outcome] == :hello end)
    await_agent_state(agent, fn state -> state.robot.safety_state == :armed end)

    {:ok, server_state} = Jido.AgentServer.state(agent)
    robot_state = server_state.agent.state.robot
    assert is_map(robot_state)
    assert robot_state.robot == TestRobot
  end

  # The bridge subscribes to BB.PubSub in its init, so once it appears among
  # the agent's plugin children the subscription is established and no
  # transition published afterwards can be missed.
  defp await_bridge_started(agent, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_bridge_started(agent, deadline)
  end

  defp poll_bridge_started(agent, deadline) do
    {:ok, server_state} = Jido.AgentServer.state(agent)

    bridge_started? =
      Enum.any?(Map.keys(server_state.children), fn
        {:plugin, BB.Jido.Plugin.Robot, _id} -> true
        _other -> false
      end)

    cond do
      bridge_started? ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("PubSubBridge was never started as a plugin child")

      true ->
        Process.sleep(10)
        poll_bridge_started(agent, deadline)
    end
  end

  defp await_agent_state(agent, satisfied?, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_agent_state(agent, satisfied?, deadline)
  end

  defp poll_agent_state(agent, satisfied?, deadline) do
    {:ok, server_state} = Jido.AgentServer.state(agent)
    state = server_state.agent.state

    cond do
      satisfied?.(state) ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("agent state never satisfied condition; last state: #{inspect(state)}")

      true ->
        Process.sleep(20)
        poll_agent_state(agent, satisfied?, deadline)
    end
  end
end
