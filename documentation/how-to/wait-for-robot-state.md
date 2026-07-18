<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to wait for a robot state

Sometimes you want an agent action to block until the robot enters a
particular state — for example, "wait until the robot is `:idle` before
issuing the next move". This guide covers the two available patterns.

## Option 1: `BB.Jido.Action.WaitForState`

The simplest case is a single, foreground wait. The action is on the agent
already (the robot plugin attaches it). Send it via the default route:

```elixir
:ok =
  Jido.AgentServer.cast(
    pid,
    Jido.Signal.new!(
      "bb.state.wait",
      %{robot: MyRobot, target: :idle, timeout: 5_000}
    )
  )
```

Return shapes:

| Outcome | Return |
|---|---|
| Robot already in `target` | `{:ok, %{state: target}}` |
| Transitions into `target` within `timeout` | `{:ok, %{state: target}}` |
| `timeout` elapses first | `{:error, :timeout}` |

The `timeout` is a total deadline — unrelated transitions arriving while
waiting don't extend it. The target may be an operational state (`:idle`,
`:executing`, custom states) or the safety state `:armed`; the already-in-
state check consults `BB.Safety.state/1` for `:armed` and
`BB.Robot.Runtime.state/1` otherwise.

The action subscribes to `[:state_machine]` before checking the current
state (so no transition can slip between check and subscription) and
unsubscribes when it returns.

> **Caveat:** this blocks the *agent process* while it waits. If your
> agent also needs to react to other signals during the wait, that
> processing is paused. For non-blocking waits, see Option 2.

## Option 2: an event-driven decision

For long waits or concurrent waits, react to the transition signal
instead. The robot plugin already forwards `bb.state.transition` signals
into the agent; scaffold an action that pattern-matches on the payload:

```bash
mix bb_jido.add_action MyRobot.OnTransition
```

```elixir
defmodule MyRobot.OnTransition do
  use Jido.Action,
    name: "on_transition",
    schema: [
      robot: [type: :atom, required: true],
      path: [type: {:list, :atom}, required: true],
      message: [type: :any, required: true]
    ]

  @impl Jido.Action
  def run(%{robot: robot, message: %BB.Message{payload: payload}}, _context) do
    case payload do
      %BB.StateMachine.Transition{to: :idle} -> handle_idle(robot)
      %BB.StateMachine.Transition{to: :error} -> handle_error(robot)
      _ -> {:ok, %{ignored: true}}
    end
  end
end
```

Attach via a plugin with `signal_routes: [{"bb.state.transition", MyRobot.OnTransition}]`.
The agent stays responsive throughout — the action runs only when the
transition actually happens, and only for the transitions you care about.

> **Rule of thumb:** if the timeout is short (sub-second), Option 1 is
> fine. If it's seconds or more, prefer Option 2.

## Pre-cached state on the plugin

`BB.Jido.Plugin.Robot` keeps a `safety_state` field in its plugin state.
The plugin routes `bb.state.transition` signals to
`BB.Jido.Action.UpdateSafetyState`, which caches safety transitions
(`:armed`, `:disarmed`, `:disarming`, `:error`) there; operational
transitions (`:idle`, `:executing`, ...) don't touch it. Read it from
another action via `context.agent.state.robot.safety_state` to skip a
Runtime lookup. This is a convenience cache — `BB.Safety.state/1` is also
cheap (ETS), so use whichever reads better in your code.

## See also

- [`BB.Jido.Action.WaitForState`](../reference/plugin-config.md#built-in-actions)
- [Reacting to PubSub](../tutorials/02-reacting-to-pubsub.md)
