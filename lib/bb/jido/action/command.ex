# SPDX-FileCopyrightText: 2026 James Harton
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
  - `{:error, :safety_disarmed}` if the command exited because the robot was
    disarmed.
  - `{:error, {:command_failed, reason}}` for any other command failure or
    process termination.

  When routed through an agent, the success map is merged into agent state
  by Jido's default strategy — result keys deliberately avoid the plugin's
  `:robot` state key.
  """

  use Jido.Action,
    name: "bb_command",
    description: "Execute a Beam Bots command",
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"],
      command: [type: :atom, required: true, doc: "Command name"],
      goal: [type: :map, default: %{}, doc: "Command goal map"],
      timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Command timeout in milliseconds"
      ]
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
            {:error, {:command_failed, reason}}
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

      {:error, :disarmed} ->
        {:error, :safety_disarmed}

      {:error, reason} ->
        {:error, {:command_failed, reason}}
    end
  end

  defp build_result(command, goal, outcome) do
    %{
      command: command,
      goal: goal,
      outcome: outcome
    }
  end
end
