# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Plugin.RobotGatingTest do
  use ExUnit.Case, async: false

  alias BB.Jido.Action.Command
  alias BB.Jido.Plugin.Robot
  alias BB.Jido.TestRobot

  defmodule GatedAgent do
    @moduledoc false
    use Jido.Agent,
      name: "bb_jido_gating_test_agent",
      plugins: [
        {BB.Jido.Plugin.Robot,
         %{robot: BB.Jido.TestRobot, gated_actions: [BB.Jido.Action.Command]}}
      ]
  end

  @jido_instance __MODULE__.JidoInstance

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    :ok
  end

  defp arm! do
    {:ok, cmd} = TestRobot.arm(%{})
    {:ok, :armed, _} = BB.Command.await(cmd)
  end

  defp gating_context(gated_actions) do
    %{config: %{robot: TestRobot, gated_actions: gated_actions}}
  end

  describe "prepare_action/3" do
    test "refuses gated actions while the robot is disarmed" do
      assert {:error, {:safety_not_armed, :disarmed}} =
               Robot.prepare_action(nil, {Command, %{}}, gating_context([Command]))
    end

    test "allows gated actions once the robot is armed" do
      arm!()

      assert {:ok, %{}} =
               Robot.prepare_action(nil, {Command, %{}}, gating_context([Command]))
    end

    test "ignores actions that are not gated" do
      assert {:ok, %{}} =
               Robot.prepare_action(nil, {Command, %{}}, gating_context([]))

      assert {:ok, %{}} =
               Robot.prepare_action(
                 nil,
                 {BB.Jido.Action.GetJointState, %{}},
                 gating_context([Command])
               )
    end

    test "gates when any action in a multi-target route is gated" do
      assert {:error, {:safety_not_armed, :disarmed}} =
               Robot.prepare_action(
                 nil,
                 [{BB.Jido.Action.GetJointState, %{}}, {Command, %{}}],
                 gating_context([Command])
               )
    end

    test "rejects a gated action targeting a robot other than the configured one" do
      arm!()

      assert {:error, {:robot_mismatch, details}} =
               Robot.prepare_action(
                 nil,
                 {Command, %{robot: SomeOtherRobot, command: :test_succeed}},
                 gating_context([Command])
               )

      assert details.configured == TestRobot
      assert details.requested == SomeOtherRobot
      assert details.action == Command
    end

    test "rejects a cross-robot target regardless of param key type" do
      arm!()

      assert {:error, {:robot_mismatch, _details}} =
               Robot.prepare_action(
                 nil,
                 {Command, %{"robot" => SomeOtherRobot}},
                 gating_context([Command])
               )
    end

    test "authorises gated actions whose params omit the robot" do
      arm!()

      assert {:ok, %{}} =
               Robot.prepare_action(
                 nil,
                 {Command, %{command: :test_succeed}},
                 gating_context([Command])
               )
    end

    test "gates actions delivered as %Jido.Instruction{} structs" do
      instruction = %Jido.Instruction{action: Command, params: %{command: :test_succeed}}

      assert {:error, {:safety_not_armed, :disarmed}} =
               Robot.prepare_action(nil, instruction, gating_context([Command]))

      assert {:error, {:safety_not_armed, :disarmed}} =
               Robot.prepare_action(nil, [instruction], gating_context([Command]))
    end

    test "rejects cross-robot params delivered as %Jido.Instruction{} structs" do
      arm!()

      instruction = %Jido.Instruction{action: Command, params: %{robot: SomeOtherRobot}}

      assert {:error, {:robot_mismatch, details}} =
               Robot.prepare_action(nil, instruction, gating_context([Command]))

      assert details.requested == SomeOtherRobot
    end

    test "gates the 3- and 4-element instruction tuple forms" do
      assert {:error, {:safety_not_armed, :disarmed}} =
               Robot.prepare_action(nil, {Command, %{}, %{}}, gating_context([Command]))

      assert {:error, {:safety_not_armed, :disarmed}} =
               Robot.prepare_action(nil, {Command, %{}, %{}, []}, gating_context([Command]))
    end

    test "rejects cross-robot keyword-list params" do
      arm!()

      assert {:error, {:robot_mismatch, details}} =
               Robot.prepare_action(
                 nil,
                 {Command, [robot: SomeOtherRobot, command: :test_succeed]},
                 gating_context([Command])
               )

      assert details.requested == SomeOtherRobot
    end

    test "fails closed on an action argument Jido cannot normalise" do
      assert {:error, {:ungateable_action_arg, _reason}} =
               Robot.prepare_action(nil, 42, gating_context([Command]))
    end

    test "passes unnormalisable arguments through when nothing is gated" do
      assert {:ok, %{}} = Robot.prepare_action(nil, 42, gating_context([]))
    end
  end

  describe "signal-routed gating through an agent" do
    setup do
      start_supervised!({Jido, name: @jido_instance})
      agent = start_supervised!({Jido.AgentServer, agent: GatedAgent, jido: @jido_instance})
      {:ok, agent: agent}
    end

    test "a gated command is refused while disarmed and runs once armed", %{agent: agent} do
      command_signal =
        Jido.Signal.new!("bb.command.execute", %{
          robot: TestRobot,
          command: :test_succeed,
          goal: %{value: :gated_hello}
        })

      # A synchronous call surfaces the prepare_action refusal directly,
      # with no reliance on log timing.
      assert {:error, refusal} = Jido.AgentServer.call(agent, command_signal)
      assert inspect(refusal) =~ "safety_not_armed"

      {:ok, server_state} = Jido.AgentServer.state(agent)
      refute Map.has_key?(server_state.agent.state, :outcome)

      arm!()
      await_agent_state(agent, fn state -> state.robot.safety_state == :armed end)

      :ok = Jido.AgentServer.cast(agent, command_signal)
      await_agent_state(agent, fn state -> state[:outcome] == :gated_hello end)
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
