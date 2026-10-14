# SPDX-FileCopyrightText: 2026 Holden Oullette
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
    notify_on_signal_processed()
    start_supervised!({TestRobot, simulation: :kinematic})
    start_supervised!({Jido, name: @jido_instance})
    agent = start_supervised!({Jido.AgentServer, agent: TestAgent, jido: @jido_instance})
    assert_bridge_started(agent)
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

  def forward_signal_processed(_event, _measurements, _metadata, test_pid) do
    send(test_pid, :agent_signal_processed)
  end

  defp notify_on_signal_processed do
    handler_id = {__MODULE__, self()}

    :telemetry.attach(
      handler_id,
      [:jido, :agent_server, :signal, :stop],
      &__MODULE__.forward_signal_processed/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  # The agent server starts plugin children in `handle_continue/2`, before it
  # handles any call, and the bridge subscribes to BB.PubSub in its init. So
  # the first call already sees the bridge, and no transition published
  # afterwards can be missed.
  defp assert_bridge_started(agent) do
    {:ok, server_state} = Jido.AgentServer.state(agent)

    assert Enum.any?(Map.keys(server_state.children), fn
             {:plugin, BB.Jido.Plugin.Robot, _id} -> true
             _other -> false
           end),
           "PubSubBridge was not started as a plugin child"
  end

  defp await_agent_state(agent, satisfied?) do
    {:ok, server_state} = Jido.AgentServer.state(agent)
    state = server_state.agent.state

    if satisfied?.(state) do
      :ok
    else
      assert_receive :agent_signal_processed,
                     2_000,
                     "agent state never satisfied condition; last state: #{inspect(state)}"

      await_agent_state(agent, satisfied?)
    end
  end
end
