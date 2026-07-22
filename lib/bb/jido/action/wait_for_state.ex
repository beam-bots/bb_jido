# SPDX-FileCopyrightText: 2026 James Harton
# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.WaitForState do
  @moduledoc """
  Jido action that waits for a Beam Bots robot to enter a target state.

  Blocks until the robot reports a transition into `:target`, or returns
  immediately if the robot is already in that state. The `[:state_machine]`
  subscription is held by a dedicated temporary process (so a caller's own
  PubSub subscriptions and mailbox are never touched) and is established
  before the current state is checked, so a transition landing between the
  two can't be missed.

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
  - `{:error, {:subscribe_failed, reason}}` if the state topic could not
    be subscribed to.
  - `{:error, {:wait_failed, reason}}` if the temporary subscriber process
    exited abnormally.

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
        doc: "Total wait deadline in milliseconds"
      ]
    ]

  alias BB.Message
  alias BB.Robot.Runtime
  alias BB.StateMachine.Transition

  @impl Jido.Action
  def run(%{robot: robot, target: target} = params, _context) do
    timeout = Map.get(params, :timeout, 30_000)
    deadline = System.monotonic_time(:millisecond) + timeout
    parent = self()
    ref = make_ref()

    # The subscription lives in a throwaway process: BB.PubSub registers
    # (and unregisters) the *calling* process per path, so subscribing
    # from the caller would silently remove any subscription the caller
    # already holds on [:state_machine] when the wait cleans up. The
    # waiter monitors the caller so that a killed caller (e.g. Jido.Exec
    # timing the action out) can't orphan the subscription until the
    # waiter's own deadline.
    {waiter, monitor} =
      spawn_monitor(fn ->
        caller = Process.monitor(parent)

        case BB.PubSub.subscribe(robot, [:state_machine], message_types: [Transition]) do
          {:ok, _pid} ->
            send(parent, {ref, :subscribed})
            send(parent, {ref, receive_transition(target, deadline, caller)})

          {:error, reason} ->
            send(parent, {ref, {:error, {:subscribe_failed, reason}}})
        end
      end)

    receive do
      {^ref, :subscribed} ->
        if in_state?(robot, target) do
          stop_waiter(waiter, monitor, ref)
          {:ok, %{state: target}}
        else
          await_waiter(ref, waiter, monitor, deadline)
        end

      {^ref, {:error, _reason} = error} ->
        Process.demonitor(monitor, [:flush])
        error

      {:DOWN, ^monitor, :process, _pid, reason} ->
        {:error, {:wait_failed, reason}}
    end
  end

  defp await_waiter(ref, waiter, monitor, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, _pid, reason} ->
        {:error, {:wait_failed, reason}}
    after
      # The waiter enforces the deadline itself; the slack makes this a
      # failsafe against a stuck waiter rather than the primary timer.
      remaining + 100 ->
        stop_waiter(waiter, monitor, ref)
        {:error, :timeout}
    end
  end

  defp stop_waiter(waiter, monitor, ref) do
    Process.demonitor(monitor, [:flush])
    Process.exit(waiter, :kill)

    # A result the waiter sent between our decision and the kill would
    # otherwise linger in the caller's mailbox.
    receive do
      {^ref, _late_result} -> :ok
    after
      0 -> :ok
    end
  end

  # Runtime.state/1 reports the operational state while armed, so :armed
  # itself is only visible through the safety controller.
  defp in_state?(robot, :armed), do: BB.Safety.state(robot) == :armed
  defp in_state?(robot, target), do: Runtime.state(robot) == target

  defp receive_transition(target, deadline, caller) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      receive do
        {:bb, [:state_machine], %Message{payload: %Transition{to: ^target}}} ->
          {:ok, %{state: target}}

        {:bb, [:state_machine], %Message{payload: %Transition{}}} ->
          receive_transition(target, deadline, caller)

        {:DOWN, ^caller, :process, _pid, _reason} ->
          # Nobody is waiting for the result any more; exiting drops the
          # subscription via the registry's monitor.
          exit(:normal)
      after
        remaining ->
          {:error, :timeout}
      end
    end
  end
end
