# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.WaitForState do
  @moduledoc """
  Jido action that waits for a Beam Bots robot to enter a target state.

  Subscribes to the `[:state_machine]` PubSub topic and blocks until the
  robot reports a transition into `:target`, or returns immediately if the
  robot is already in that state.

  ## Schema

  - `:robot` — the robot module (required).
  - `:target` — the desired robot state atom (required, e.g. `:idle`,
    `:armed`).
  - `:timeout` — millisecond timeout (default `30_000`).

  ## Returns

  - `{:ok, %{state: target}}` when the state is reached.
  - `{:error, :timeout}` if the timeout elapses first.

  ## Warning

  This action blocks the calling process while waiting. When invoked
  directly from a Jido agent it will block the agent server; prefer
  running it from a dedicated process or via a workflow when long waits
  are expected.
  """

  use Jido.Action,
    name: "bb_wait_for_state",
    description: "Wait for a Beam Bots robot to enter a target state",
    category: "robotics",
    tags: ["beam-bots", "robot", "observation"],
    output_schema: [
      state: [type: :atom, doc: "The state that was reached"]
    ],
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"],
      target: [type: :atom, required: true, doc: "Desired robot state"],
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Wait timeout in milliseconds"
      ]
    ]

  alias BB.Message
  alias BB.Robot.Runtime
  alias BB.StateMachine.Transition

  @impl Jido.Action
  def run(%{robot: robot, target: target} = params, _context) do
    timeout = Map.get(params, :timeout, 30_000)

    case Runtime.state(robot) do
      ^target ->
        {:ok, %{state: target}}

      _other ->
        wait_for_transition(robot, target, timeout)
    end
  end

  defp wait_for_transition(robot, target, timeout) do
    case BB.PubSub.subscribe(robot, [:state_machine], message_types: [Transition]) do
      {:ok, _pid} ->
        try do
          receive_transition(target, timeout)
        after
          BB.PubSub.unsubscribe(robot, [:state_machine])
        end

      {:error, reason} ->
        {:error, {:subscribe_failed, reason}}
    end
  end

  defp receive_transition(target, timeout) do
    receive do
      {:bb, [:state_machine], %Message{payload: %Transition{to: ^target}}} ->
        {:ok, %{state: target}}

      {:bb, [:state_machine], %Message{payload: %Transition{}}} ->
        receive_transition(target, timeout)
    after
      timeout ->
        {:error, :timeout}
    end
  end
end
