# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.SignalTest do
  use ExUnit.Case, async: true

  alias BB.Jido.Signal, as: SignalMap
  alias BB.Message
  alias BB.Parameter.Changed
  alias BB.Safety.HardwareError
  alias BB.StateMachine.Transition

  defp message(payload, opts \\ []) do
    %Message{
      monotonic_time: 0,
      wall_time: 0,
      node: node(),
      frame_id: Keyword.get(opts, :frame_id, :base),
      payload: payload,
      robot: Keyword.get(opts, :robot)
    }
  end

  describe "from_pubsub/3" do
    test "maps state transitions to bb.state.transition" do
      msg = message(%Transition{from: :disarmed, to: :armed})

      signal = SignalMap.from_pubsub(SomeRobot, [:state_machine], msg)

      assert signal.type == "bb.state.transition"
      assert signal.source == "/bb/SomeRobot"
      assert signal.data.robot == SomeRobot
      assert signal.data.path == [:state_machine]
      assert signal.data.message == msg
    end

    test "maps safety hardware errors to bb.safety.error" do
      msg = message(%HardwareError{path: [:joint1], error: :oops})

      signal = SignalMap.from_pubsub(SomeRobot, [:safety, :error], msg)

      assert signal.type == "bb.safety.error"
      assert signal.data.message.payload == %HardwareError{path: [:joint1], error: :oops}
    end

    test "maps parameter changes to bb.parameter.changed" do
      payload = %Changed{path: [:controller, :gain], old_value: 1.0, new_value: 2.0}
      msg = message(payload)

      signal = SignalMap.from_pubsub(SomeRobot, [:param, :controller, :gain], msg)

      assert signal.type == "bb.parameter.changed"
      assert signal.data.message.payload == payload
    end

    test "maps unknown payloads to bb.pubsub.<path>" do
      payload = %{__struct__: SomeStruct, foo: 1}
      msg = message(payload)

      signal = SignalMap.from_pubsub(SomeRobot, [:sensor, :imu], msg)

      assert signal.type == "bb.pubsub.sensor.imu"
    end

    test "falls back to message.robot when caller-supplied robot is nil" do
      msg = message(%Transition{from: :armed, to: :disarmed}, robot: OtherRobot)

      signal = SignalMap.from_pubsub(nil, [:state_machine], msg)

      assert signal.source == "/bb/OtherRobot"
      assert signal.data.robot == OtherRobot
    end
  end

  describe "type_for/2" do
    test "specialises by payload module" do
      assert SignalMap.type_for([:state_machine], %Transition{from: :a, to: :b}) ==
               "bb.state.transition"

      assert SignalMap.type_for([:safety, :error], %HardwareError{path: [], error: :x}) ==
               "bb.safety.error"

      assert SignalMap.type_for([:param, :gain], %Changed{path: [:gain]}) ==
               "bb.parameter.changed"
    end

    test "defaults to bb.pubsub.<dotted path>" do
      assert SignalMap.type_for([:sensor, :joint_state], nil) == "bb.pubsub.sensor.joint_state"
      assert SignalMap.type_for([], nil) == "bb.pubsub."
    end
  end

  describe "source/1" do
    test "renders /bb/<robot module>" do
      assert SignalMap.source(MyRobot) == "/bb/MyRobot"
    end

    test "returns /bb for a nil robot" do
      assert SignalMap.source(nil) == "/bb"
    end
  end
end
