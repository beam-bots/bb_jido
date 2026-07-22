# SPDX-FileCopyrightText: 2026 James Harton
# SPDX-FileCopyrightText: 2026 Holden Oullette
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
      assert state.last_safety_error == nil
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
      assert {"state.transition", BB.Jido.Action.UpdateSafetyState} in routes
      assert {"safety.error", BB.Jido.Action.RecordSafetyError} in routes
    end

    test "is a singleton and rejects as: aliasing" do
      assert Robot.singleton?()

      assert_raise ArgumentError, ~r/singleton/, fn ->
        Jido.Plugin.Instance.new({Robot, [as: :left, robot: BB.Jido.TestRobot]})
      end
    end

    test "advertises the standard robot actions" do
      actions = Robot.actions()

      assert BB.Jido.Action.Command in actions
      assert BB.Jido.Action.Reactor in actions
      assert BB.Jido.Action.WaitForState in actions
      assert BB.Jido.Action.GetJointState in actions
      assert BB.Jido.Action.UpdateSafetyState in actions
      assert BB.Jido.Action.RecordSafetyError in actions
    end
  end

  describe "config_schema" do
    test "applies defaults and accepts a minimal config" do
      assert {:ok, config} = Zoi.parse(Robot.config_schema(), %{robot: BB.Jido.TestRobot})

      assert config.robot == BB.Jido.TestRobot
      assert config.topics == [[:state_machine]]
      assert config.message_types == []
      assert config.gated_actions == []
      refute Map.has_key?(config, :throttle_ms)
    end

    test "accepts real Jido.Action modules as gated_actions" do
      assert {:ok, config} =
               Zoi.parse(Robot.config_schema(), %{
                 robot: BB.Jido.TestRobot,
                 gated_actions: [BB.Jido.Action.Command, BB.Jido.Action.Reactor]
               })

      assert config.gated_actions == [BB.Jido.Action.Command, BB.Jido.Action.Reactor]
    end

    test "rejects a config without :robot" do
      assert {:error, _errors} = Zoi.parse(Robot.config_schema(), %{})
    end

    test "rejects a nil or non-robot :robot" do
      assert {:error, _errors} = Zoi.parse(Robot.config_schema(), %{robot: nil})
      assert {:error, _errors} = Zoi.parse(Robot.config_schema(), %{robot: NoSuchRobot})
      assert {:error, _errors} = Zoi.parse(Robot.config_schema(), %{robot: String})
    end

    test "rejects gated_actions entries that are not real Jido.Action modules" do
      for bad <- [[BB.Jido.Action.Comand], [nil], [String]] do
        assert {:error, _errors} =
                 Zoi.parse(Robot.config_schema(), %{
                   robot: BB.Jido.TestRobot,
                   gated_actions: bad
                 })
      end
    end

    test "rejects unrecognised config keys instead of silently dropping them" do
      assert {:error, errors} =
               Zoi.parse(Robot.config_schema(), %{
                 robot: BB.Jido.TestRobot,
                 gated_action: [BB.Jido.Action.Command]
               })

      assert Enum.any?(errors, &(&1.code == :unrecognized_key))
    end

    test "rejects a non-positive throttle" do
      assert {:error, _errors} =
               Zoi.parse(Robot.config_schema(), %{robot: BB.Jido.TestRobot, throttle_ms: 0})
    end
  end

  describe "manifest metadata" do
    test "declares description, category, and capabilities" do
      manifest = Robot.manifest()

      assert manifest.description =~ "Beam Bots"
      assert manifest.category == "robotics"
      assert :robot_control in manifest.capabilities
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
