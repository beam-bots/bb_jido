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

  `{:ok, %{robot: ..., positions: %{joint => rad}, velocities: %{joint => rad_s}}}`.
  """

  use Jido.Action,
    name: "bb_get_joint_state",
    description: "Read current joint positions and velocities",
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"]
    ]

  alias BB.Robot.Runtime

  @impl Jido.Action
  def run(%{robot: robot}, _context) do
    {:ok,
     %{
       robot: robot,
       positions: Runtime.positions(robot),
       velocities: Runtime.velocities(robot)
     }}
  end
end
