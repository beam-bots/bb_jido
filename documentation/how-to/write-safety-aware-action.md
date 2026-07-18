<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to write a safety-aware action

A safety-aware action refuses to run unless `BB.Safety.state(robot) == :armed`.
This guide shows the recommended pattern: use `BB.Jido.Action.SafetyAware`.

## When to do this

Use the safety guard for any action that **physically moves the robot**.
For read-only actions (`BB.Jido.Action.GetJointState`, perception, logging)
the guard is unnecessary overhead.

## The recipe

Scaffold the action with `--safety-aware`:

```bash
mix bb_jido.add_action MyRobot.Actions.MoveSomewhere \\
  --safety-aware \\
  --description "Drive the robot to a configured pose"
```

The generator produces a module with the mixin already in place. Add
your own fields to the schema and fill in `run/2`:

```elixir
defmodule MyRobot.Actions.MoveSomewhere do
  use Jido.Action,
    name: "move_somewhere",
    description: "Drive the robot to a configured pose",
    schema: [
      robot: [type: :atom, required: true],
      pose: [type: :map, required: true]
    ]

  use BB.Jido.Action.SafetyAware

  @impl Jido.Action
  def run(%{robot: robot, pose: pose}, _context) do
    BB.Jido.Action.Command.run(
      %{robot: robot, command: :move_to, goal: pose},
      %{}
    )
  end
end
```

`SafetyAware` wraps your `run/2` at compile time. The guard is invoked
*before* yours, so by the time `MyRobot.Actions.MoveSomewhere.run/2` runs
the robot is guaranteed to be armed.

## Error shapes

| Robot state | Return |
|---|---|
| `:armed` | passes through to your `run/2` |
| `:disarmed` / `:disarming` / `:error` | `{:error, {:safety_not_armed, state}}` |
| `robot` not in params or context | `{:error, :robot_not_specified}` |

## Where the robot module is looked up

`SafetyAware` checks two places, in order:

1. `params[:robot]` — the value passed via the action's schema.
2. `context[:robot]` — useful when a parent action injects context.

If your action doesn't accept a `:robot` field in its schema, set it from
elsewhere into context before invoking, e.g.:

```elixir
MyRobot.Actions.MoveSomewhere.run(%{pose: pose}, %{robot: MyRobot})
```

## Don't double-guard

`BB.Jido.Action.Command` already maps `:disarmed` exits onto
`{:error, :safety_disarmed}`. The safety guard adds an *early* refusal so
the command is never even started — useful if starting the command would
itself have side effects (logging, telemetry, allocating resources).

## Plugin-level gating

For signal-routed execution, `BB.Jido.Plugin.Robot` can enforce the same
guard centrally: list the actions in the plugin's `:gated_actions` config
and they're refused with `{:error, {:safety_not_armed, state}}` before
they execute, no mixin required. Use the mixin when the action must be
guarded everywhere it's called (including reactor steps and direct
`run/2` calls); use `:gated_actions` when you want one agent-level policy
for routed signals. They compose — gating both ways is harmless.

## See also

- [`BB.Jido.Action.SafetyAware`](../reference/error-taxonomy.md#safety_not_armed)
  — error reference.
- [Understanding safety](https://hexdocs.pm/bb/understanding-safety.html) —
  the BB-level safety model.
