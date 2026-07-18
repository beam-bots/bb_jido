# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.WaitForState do
  @moduledoc """
  Jido action that waits for a Beam Bots robot to enter a target state.

  Subscribes to the `[:state_machine]` PubSub topic and blocks until the
  robot reports a transition into `:target`, or returns immediately if the
  robot is already in that state. The subscription is established before
  the current state is checked, so a transition landing between the two
  can't be missed.

  The target may be either an operational state (`:idle`, `:executing`,
  or your robot's custom states, checked via `BB.Robot.Runtime.state/1`)
  or the safety state `:armed` (checked via `BB.Safety.state/1` —
  `BB.Robot.Runtime.state/1` reports the operational state while armed,
  never `:armed` itself). The remaining safety states (`:disarmed`,
  `:disarming`, `:error`) are reported by both.

  ## Schema

  - `:robot` — the robot module (required).
  - `:target` — the desired robot state atom (required, e.g. `:idle`,
    `:armed`).
  - `:timeout` — millisecond timeout (default `30_000`). This is a total
    deadline: unrelated transitions arriving while waiting don't extend it.

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
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"],
      target: [type: :atom, required: true, doc: "Desired robot state"],
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Total wait deadline in milliseconds"
      ]
    ]

  alias BB.Message
  alias BB.Robot.Runtime
  alias BB.StateMachine.Transition

  @impl Jido.Action
  def run(%{robot: robot, target: target} = params, _context) do
    timeout = Map.get(params, :timeout, 30_000)

    case BB.PubSub.subscribe(robot, [:state_machine], message_types: [Transition]) do
      {:ok, _pid} ->
        try do
          await_target(robot, target, timeout)
        after
          BB.PubSub.unsubscribe(robot, [:state_machine])
          drain_transitions()
        end

      {:error, reason} ->
        {:error, {:subscribe_failed, reason}}
    end
  end

  defp await_target(robot, target, timeout) do
    if in_state?(robot, target) do
      {:ok, %{state: target}}
    else
      deadline = System.monotonic_time(:millisecond) + timeout
      receive_transition(target, deadline)
    end
  end

  # Runtime.state/1 reports the operational state while armed, so :armed
  # itself is only visible through the safety controller.
  defp in_state?(robot, :armed), do: BB.Safety.state(robot) == :armed
  defp in_state?(robot, target), do: Runtime.state(robot) == target

  defp receive_transition(target, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      receive do
        {:bb, [:state_machine], %Message{payload: %Transition{to: ^target}}} ->
          {:ok, %{state: target}}

        {:bb, [:state_machine], %Message{payload: %Transition{}}} ->
          receive_transition(target, deadline)
      after
        remaining ->
          {:error, :timeout}
      end
    end
  end

  # Transitions delivered between the last receive and the unsubscribe
  # would otherwise be left in the caller's mailbox.
  defp drain_transitions do
    receive do
      {:bb, [:state_machine], %Message{}} -> drain_transitions()
    after
      0 -> :ok
    end
  end
end
