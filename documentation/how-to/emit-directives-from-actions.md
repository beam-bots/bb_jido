<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to emit signals from an action

A Jido action can return *directives* alongside its result. The most
useful one for `bb_jido` is `Jido.Agent.Directive.Emit`, which dispatches
a follow-up signal. This lets an action say "I finished — now do this
next" without imperatively calling other actions.

## The basic shape

Scaffold the action with `mix bb_jido.add_action MyRobot.Actions.PickThenAnnounce`,
then replace the stub `run/2`:

```elixir
defmodule MyRobot.Actions.PickThenAnnounce do
  use Jido.Action,
    name: "pick_then_announce",
    schema: [robot: [type: :atom, required: true], target: [type: :atom, required: true]]

  alias Jido.Agent.Directive.Emit

  @impl Jido.Action
  def run(%{robot: robot, target: target}, _context) do
    case BB.Jido.Action.Reactor.run(
           %{
             robot: robot,
             reactor: MyRobot.Workflow.Pick,
             inputs: %{target: target}
           },
           %{}
         ) do
      {:ok, result} ->
        followup =
          Jido.Signal.new!("my_robot.pick.completed", %{target: target})

        {:ok, result, %Emit{signal: followup}}

      {:error, reason} ->
        failure =
          Jido.Signal.new!("my_robot.pick.failed", %{target: target, reason: reason})

        {:ok, %{target: target, recovered: false}, %Emit{signal: failure}}
    end
  end
end
```

The `Emit` directive is the third element of the return tuple. The
runtime dispatches `signal` back through the agent's router, where any
matching `signal_routes` will fire.

## Multiple directives

Return a list to emit several signals:

```elixir
{:ok, result,
 [
   %Emit{signal: log_signal},
   %Emit{signal: followup_signal}
 ]}
```

## Pick a dispatch target

By default the runtime dispatches to the agent itself (`self()`). Pass
`:dispatch` on the `Emit` struct to send elsewhere:

```elixir
%Emit{
  signal: signal,
  dispatch: {:pubsub, topic: "robot_events"}
}
```

See `Jido.Signal.Dispatch` for the list of adapters (`:pid`, `:pubsub`,
`:bus`, `:http`, `:logger`, etc.).

## Don't bypass the router for cross-action chaining

You *could* call `MyRobot.Actions.Next.run(params, %{})` directly from
inside your action — actions are plain modules. Prefer emitting a signal
when:

- The next action lives in a different plugin.
- You want telemetry/observability on the hand-off.
- Another listener might also want to react (multi-cast).

Direct calls are fine when the chain is private to one module and you
don't want it observable.

## See also

- [`Jido.Agent.Directive`](https://hexdocs.pm/jido/Jido.Agent.Directive.html)
  — the full directive vocabulary (`Emit`, `Spawn`, `Schedule`, `Stop`, …).
- [Running Workflows](../tutorials/03-running-workflows.md) — the
  end-to-end example uses `Emit` to chain reactor success into a signal.
