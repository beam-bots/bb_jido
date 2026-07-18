# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.GetJointState do
  @moduledoc """
  Jido action that reads the current joint positions and velocities for a
  Beam Bots robot.

  ## Schema

  - `:robot` — the robot module (required).

  ## Returns

  `{:ok, %{positions: %{joint => rad}, velocities: %{joint => rad_s}}, effects}`
  where `effects` contains a `Jido.Agent.StateOp.SetPath` that stores the
  same map at `agent.state.robot.last_joint_state` when the action runs
  through an agent with `BB.Jido.Plugin.Robot` mounted.
  """

  use Jido.Action,
    name: "bb_get_joint_state",
    description: "Read current joint positions and velocities",
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"]
    ]

  alias BB.Robot.Runtime
  alias Jido.Agent.StateOp

  @impl Jido.Action
  def run(%{robot: robot}, _context) do
    joint_state = %{
      positions: Runtime.positions(robot),
      velocities: Runtime.velocities(robot)
    }

    {:ok, joint_state, [%StateOp.SetPath{path: [:robot, :last_joint_state], value: joint_state}]}
  end
end
