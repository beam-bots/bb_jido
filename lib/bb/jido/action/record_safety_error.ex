# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.RecordSafetyError do
  @moduledoc """
  Jido action that records the most recent safety hardware error in the
  agent's plugin state.

  `BB.Jido.Plugin.Robot` routes `bb.safety.error` signals to this action, so
  its params are the signal's data (`%{robot: ..., path: ..., message:
  %BB.Message{}}`). The `%BB.Safety.HardwareError{}` payload is stored at
  `agent.state.robot.last_safety_error` via a `Jido.Agent.StateOp.SetPath`
  effect. Params without a hardware-error payload are ignored.

  ## Returns

  - `{:ok, %{}, [%Jido.Agent.StateOp.SetPath{}]}` for hardware errors.
  - `{:ok, %{}}` for anything else.
  """

  use Jido.Action,
    name: "bb_record_safety_error",
    description: "Record a bb.safety.error hardware error in agent state",
    category: "robotics",
    tags: ["beam-bots", "robot", "observation"],
    schema: [
      message: [type: :any, doc: "Bridged %BB.Message{} carrying the error"]
    ]

  alias BB.Message
  alias BB.Safety.HardwareError
  alias Jido.Agent.StateOp

  @impl Jido.Action
  def run(%{message: %Message{payload: %HardwareError{} = error}}, _context) do
    {:ok, %{}, [%StateOp.SetPath{path: [:robot, :last_safety_error], value: error}]}
  end

  def run(_params, _context), do: {:ok, %{}}
end
