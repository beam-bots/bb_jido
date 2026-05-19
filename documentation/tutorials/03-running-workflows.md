<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Running Workflows

`BB.Jido.Action.Command` runs a single robot command. For more involved
sequences — pick-and-place, calibration, an assembly step — you almost
always want a [`bb_reactor`] workflow. This tutorial shows how to invoke a
reactor *from* an agent: the agent decides "this is what I want to do
next", the reactor handles the structured execution and compensation.

[`bb_reactor`]: https://hexdocs.pm/bb_reactor

## Prerequisites

- [Tutorials 1](01-your-first-agent.md) and [2](02-reacting-to-pubsub.md).
- Familiarity with `bb_reactor`.
- Install it with Igniter (`bb_jido` doesn't depend on it):

  ```bash
  mix igniter.install bb_reactor
  ```

## Step 1: Define a reactor

Workflows are reactor modules. A minimal one that runs a single command:

```elixir
defmodule MyRobot.Workflow.PickAndPlace do
  use Reactor

  middlewares do
    middleware BB.Reactor.Middleware.Context
  end

  input :pick_pose
  input :place_pose

  step :move_to_pick do
    impl {BB.Reactor.Step.Command, command: :move_to}
    argument :target, input(:pick_pose)
  end

  step :grasp do
    impl {BB.Reactor.Step.Command, command: :close_gripper}
    wait_for :move_to_pick
  end

  step :move_to_place do
    impl {BB.Reactor.Step.Command, command: :move_to}
    argument :target, input(:place_pose)
    wait_for :grasp
  end

  step :release do
    impl {BB.Reactor.Step.Command, command: :open_gripper}
    wait_for :move_to_place
  end

  return :release
end
```

The `BB.Reactor.Middleware.Context` middleware reads
`context.private.bb_robot` and exposes it to every step.

## Step 2: Invoke the reactor from the agent

`BB.Jido.Action.Command`'s reactor cousin is `BB.Jido.Action.Reactor`. It's
already on the agent — the robot plugin attaches it. Send it via the
default route, `bb.reactor.run`:

```elixir
:ok =
  Jido.AgentServer.cast(
    pid,
    Jido.Signal.new!(
      "bb.reactor.run",
      %{
        robot: MyRobot,
        reactor: MyRobot.Workflow.PickAndPlace,
        inputs: %{
          pick_pose: %{x: 0.2, y: 0.0, z: 0.1},
          place_pose: %{x: 0.0, y: 0.2, z: 0.1}
        }
      }
    )
  )
```

That's it. The action injects `context.private.bb_robot = MyRobot` and
calls `Reactor.run/3`. On success it returns
`{:ok, %{robot: ..., reactor: ..., result: result}}` to the agent.

> **Why didn't I have to thread the robot module through every step?**
> Because the reactor middleware reads it from context. Each step picks
> the robot out of `context.private.bb` (a `%BB.Reactor.Context{}`).

## Step 3: Compose decisions before invoking

The whole point of agents is to *decide* before running a structured
workflow. Scaffold a higher-level action that wraps the reactor call:

```bash
mix bb_jido.add_action MyRobot.Actions.PickRedBlock
```

Then replace the stub `run/2` so it selects inputs and invokes the
reactor:

```elixir
defmodule MyRobot.Actions.PickRedBlock do
  use Jido.Action,
    name: "pick_red_block",
    schema: [robot: [type: :atom, required: true]]

  alias Jido.Agent.Directive.Emit

  @impl Jido.Action
  def run(%{robot: robot}, _context) do
    pick_pose = locate_red_block(robot)
    place_pose = %{x: 0.0, y: 0.2, z: 0.1}

    BB.Jido.Action.Reactor.run(
      %{
        robot: robot,
        reactor: MyRobot.Workflow.PickAndPlace,
        inputs: %{pick_pose: pick_pose, place_pose: place_pose}
      },
      %{}
    )
  end

  defp locate_red_block(_robot), do: %{x: 0.2, y: 0.0, z: 0.1}
end
```

You can call `BB.Jido.Action.Reactor.run/2` directly — actions are plain
Elixir modules.

## Step 4: Handle reactor outcomes

`BB.Jido.Action.Reactor` maps reactor's three return shapes onto
bb_jido's error taxonomy:

| Reactor returns | Action returns |
|---|---|
| `{:ok, result}` | `{:ok, %{result: result, ...}}` |
| `{:ok, result, _struct}` | `{:ok, %{result: result, ...}}` |
| `{:halted, halted}` | `{:error, {:reactor_halted, halted}}` |
| `{:error, errors}` | `{:error, {:reactor_failed, errors}}` |

If your workflow has compensation steps, they run before
`{:error, ...}` is returned — that's the reactor's saga behaviour, not
the action's job.

> **Should the agent retry or compensate?** That's an application
> decision. The reactor unwinds *its own* steps; the agent decides what
> happens next (re-plan, escalate, ask a human). See [Layered
> architecture](../topics/layered-architecture.md).

## Step 5: Chain the result into another signal

Actions can emit signals via directives. To follow a successful pick with
a celebratory state-machine transition, return an `Emit` directive:

```elixir
alias Jido.Agent.Directive.Emit

def run(params, _ctx) do
  case BB.Jido.Action.Reactor.run(params, %{}) do
    {:ok, result} ->
      followup =
        Jido.Signal.new!("my_robot.pick.completed", %{
          target: params[:target]
        })

      {:ok, result, %Emit{signal: followup}}

    {:error, reason} ->
      {:error, reason}
  end
end
```

The runtime dispatches the follow-up signal back through the router. Any
plugin that listens for `my_robot.pick.completed` will fire.

## What you've built

```
bb.reactor.run signal
        │
        ▼
BB.Jido.Action.Reactor
        │  Reactor.run/3 with private.bb_robot = MyRobot
        ▼
PickAndPlace ── steps run BB commands via BB.Reactor.Step.Command
        │
        ▼
{:ok, result}  →  agent
        │
        ▼ (optional directive)
my_robot.pick.completed signal  →  back into the router
```

## Where next

- [Layered architecture](../topics/layered-architecture.md) — why the
  agent dispatches reactors rather than running step logic directly.
- [Emit directives from actions](../how-to/emit-directives-from-actions.md)
  — more on signal chaining.
- [Wait for robot state](../how-to/wait-for-robot-state.md) — block
  inside an action until the robot reaches a given state.
