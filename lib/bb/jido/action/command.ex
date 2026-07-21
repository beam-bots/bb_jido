# SPDX-FileCopyrightText: 2026 James Harton
# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.Command do
  @moduledoc """
  Jido action that executes a Beam Bots command.

  Bridges Jido's action system to BB's command infrastructure: starts the
  named command on the robot, awaits its result with `BB.Command.await/2`,
  and maps the outcome into the canonical bb_jido error taxonomy.

  ## Schema

  - `:robot` — the robot module (required).
  - `:command` — the command name as an atom (required).
  - `:goal` — the goal map passed to the command (default `%{}`).
  - `:timeout` — millisecond timeout for `BB.Command.await/2` (default
    `30_000`).

  ## Returns

  - `{:ok, %{command: ..., goal: ..., outcome: ...}}` on success.
  - `{:error, :safety_disarmed}` if the robot rejected the command because
    it was disarmed, or the command process was stopped by a disarm.
  - `{:error, {:command_failed, reason}}` for any other command failure or
    process termination. `reason` is passed through exactly once —
    failures that `BB.Command.await/2` already reports as
    `{:command_failed, reason}` (crash, `:timeout`, `:noproc`) are not
    wrapped again.

  A disarm that happens *mid-flight* stops the command process, but the
  awaited value is still whatever the command's `result/1` callback
  returns — commands that want callers to see `:safety_disarmed` in that
  case should surface `:disarmed` (or a `{:shutdown, :disarmed}` reason)
  from `result/1`.

  When routed through an agent, the success map is merged into agent state
  by Jido's default strategy — result keys deliberately avoid the plugin's
  `:robot` state key.

  ## Agent-routed execution caveats

  When this action runs via a signal route (rather than a direct `run/2`
  call), it executes under `Jido.Exec`, which has two effects:

  - `Jido.Exec` enforces its own default 30s execution timeout regardless
    of the `:timeout` param. A `:timeout` above 30s only takes effect if
    the route or instruction sets a matching `Jido.Exec` `:timeout`
    option (or the `:jido_action` `:default_timeout` config is raised).
  - Error tuples are normalised into `Jido.Action.Error` exception
    structs; the tags above then appear under the error's details rather
    than as bare tuples.
  """

  use Jido.Action,
    name: "bb_command",
    description: "Execute a Beam Bots command",
    category: "robotics",
    tags: ["beam-bots", "robot", "command"],
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"],
      command: [type: :atom, required: true, doc: "Command name"],
      goal: [type: :map, default: %{}, doc: "Command goal map"],
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Command timeout in milliseconds"
      ]
    ],
    output_schema: [
      command: [type: :atom, doc: "The command that ran"],
      goal: [type: :map, doc: "The goal it was given"],
      outcome: [type: :any, doc: "The command's result value"]
    ]

  alias BB.Jido.Telemetry

  @impl Jido.Action
  def run(%{robot: robot, command: command} = params, _context) do
    goal = Map.get(params, :goal, %{})
    timeout = Map.get(params, :timeout, 30_000)

    Telemetry.span(
      [:bb_jido, :action, :command],
      %{robot: robot, command: command},
      fn ->
        case apply(robot, command, [goal]) do
          {:ok, pid} ->
            await_command(pid, command, goal, timeout)

          {:error, reason} ->
            {:error, command_error(reason)}
        end
      end
    )
  end

  defp await_command(pid, command, goal, timeout) do
    case BB.Command.await(pid, timeout) do
      {:ok, outcome} ->
        {:ok, build_result(command, goal, outcome)}

      {:ok, outcome, _opts} ->
        {:ok, build_result(command, goal, outcome)}

      {:error, reason} ->
        {:error, command_error(reason)}
    end
  end

  # BB.Command.await/2 pre-wraps infrastructure failures (crash, :timeout,
  # :noproc) as {:command_failed, reason}; unwrap before mapping so those
  # reasons aren't wrapped twice.
  defp command_error({:command_failed, reason}), do: command_error(reason)
  defp command_error(:disarmed), do: :safety_disarmed
  defp command_error({:shutdown, :disarmed}), do: :safety_disarmed

  defp command_error(%BB.Error.State.NotAllowed{current_state: :disarmed}),
    do: :safety_disarmed

  defp command_error(reason), do: {:command_failed, reason}

  defp build_result(command, goal, outcome) do
    %{
      command: command,
      goal: goal,
      outcome: outcome
    }
  end
end
