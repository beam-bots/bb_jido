# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.UpdateSafetyState do
  @moduledoc """
  Jido action that caches the robot's safety state in the agent's plugin
  state.

  `BB.Jido.Plugin.Robot` routes `bb.state.transition` signals to this action,
  so its params are the signal's data (`%{robot: ..., path: ..., message:
  %BB.Message{}}`). When the transition targets one of the safety
  controller's states (`:armed`, `:disarmed`, `:disarming`, or `:error`) the
  action records it at `agent.state.robot.safety_state` via a
  `Jido.Agent.StateOp.SetPath` effect. Operational state-machine transitions
  (e.g. `:idle`, `:executing`) and unrecognised params leave the cache
  untouched.

  ## Returns

  - `{:ok, %{}, [%Jido.Agent.StateOp.SetPath{}]}` for safety transitions.
  - `{:ok, %{}}` for anything else.
  """

  use Jido.Action,
    name: "bb_update_safety_state",
    description: "Cache the robot safety state from a bb.state.transition signal",
    category: "robotics",
    tags: ["beam-bots", "robot", "observation"],
    schema: [
      message: [type: :any, doc: "Bridged %BB.Message{} carrying the transition"]
    ]

  alias BB.Message
  alias BB.StateMachine.Transition
  alias Jido.Agent.StateOp

  # The [:state_machine] topic carries both safety-controller transitions and
  # operational robot-state transitions; only the safety vocabulary
  # (`BB.Safety.state/1`) may be cached as :safety_state.
  @safety_states [:armed, :disarmed, :disarming, :error]

  @impl Jido.Action
  def run(%{message: %Message{payload: %Transition{to: to}}}, _context)
      when to in @safety_states do
    {:ok, %{}, [%StateOp.SetPath{path: [:robot, :safety_state], value: to}]}
  end

  def run(_params, _context), do: {:ok, %{}}
end
