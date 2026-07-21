# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.GetJointStateTest do
  use ExUnit.Case, async: false

  alias BB.Jido.Action.GetJointState
  alias BB.Jido.TestRobot
  alias Jido.Agent.StateOp

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    :ok
  end

  test "returns joint positions and velocities and stores them as a state op" do
    assert {:ok, joint_state, [op]} = GetJointState.run(%{robot: TestRobot}, %{})

    assert %{positions: positions, velocities: velocities} = joint_state
    assert Map.has_key?(positions, :joint1)
    assert Map.has_key?(velocities, :joint1)

    assert %StateOp.SetPath{path: [:robot, :last_joint_state], value: ^joint_state} = op
  end
end
