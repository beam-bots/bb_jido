# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Plugin.RobotTest do
  use ExUnit.Case, async: true

  alias BB.Jido.Plugin.Robot

  describe "mount/2" do
    test "returns initial robot state for valid config" do
      assert {:ok, state} = Robot.mount(:agent_placeholder, %{robot: SomeRobot})
      assert state.robot == SomeRobot
      assert state.safety_state == :unknown
      assert state.last_joint_state == %{}
    end

    test "fails when robot module is missing" do
      assert {:error, _msg} = Robot.mount(:agent_placeholder, %{})
    end
  end

  describe "declarative configuration" do
    test "advertises the canonical signal routes (unprefixed; Jido prefixes with the plugin name at compile-time on the agent)" do
      routes = Robot.signal_routes()

      assert {"command.execute", BB.Jido.Action.Command} in routes
      assert {"reactor.run", BB.Jido.Action.Reactor} in routes
      assert {"state.wait", BB.Jido.Action.WaitForState} in routes
    end

    test "advertises the standard robot actions" do
      actions = Robot.actions()

      assert BB.Jido.Action.Command in actions
      assert BB.Jido.Action.Reactor in actions
      assert BB.Jido.Action.WaitForState in actions
      assert BB.Jido.Action.GetJointState in actions
    end
  end

  describe "child_spec/1" do
    test "returns a PubSubBridge child spec parameterised by robot" do
      spec = Robot.child_spec(%{robot: SomeRobot})

      assert %{
               id: {Robot, :pub_sub_bridge, SomeRobot},
               start: {BB.Jido.PubSubBridge, :start_link, [opts]},
               restart: :transient
             } = spec

      assert Keyword.get(opts, :robot) == SomeRobot
      assert Keyword.get(opts, :topics) == [[:state_machine]]
      assert is_pid(Keyword.fetch!(opts, :agent))
    end
  end
end
