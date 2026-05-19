<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Your First Agent

In this tutorial you'll wire a Beam Bots robot up to a [Jido] agent and
ask the agent to execute a robot command by sending it a signal. By the
end you'll have a running supervision tree containing your robot, a Jido
instance, and one live agent.

[Jido]: https://hex.pm/packages/jido

## Prerequisites

- Completed the [Beam Bots tutorials](https://hexdocs.pm/bb), or at least
  [First Robot](https://hexdocs.pm/bb/01-first-robot.html) and
  [Commands and State Machine](https://hexdocs.pm/bb/05-commands.html).
- An Elixir project that already declares a working robot module (we'll
  call it `MyRobot` throughout).

> **For Roboticists:** Where a behaviour tree would tick every frame, a
> Jido agent stays idle until something happens. Signals are the inputs —
> they're either casually sent by application code (like a teleop request)
> or bridged in from BB's PubSub.

> **For Elixirists:** A Jido agent is a `GenServer` plus a router. You give
> it a list of plugins; each plugin contributes actions, signal routes, and
> child processes. Sending a signal looks up an action in the router and
> runs it inside the agent process.

## Step 1: Install bb_jido

One command sets up everything you need:

```bash
mix igniter.install bb_jido --robot MyRobot
```

This:

1. Adds `{:bb_jido, "~> 0.1"}` to your `mix.exs`.
2. Creates `lib/my_app/jido.ex` — your application's [Jido instance], the
   supervisor under which agents will run.
3. Adds `{Jido, [name: MyApp.Jido]}` to your application's supervision
   tree.
4. Creates `lib/my_robot/agent.ex` — an agent module that attaches
   `BB.Jido.Plugin.Robot` for `MyRobot`.

[Jido instance]: ../topics/plugin-lifecycle.md#where-the-agent-lives

After the installer runs you'll have:

```elixir
# lib/my_app/jido.ex
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

```elixir
# lib/my_robot/agent.ex
defmodule MyRobot.Agent do
  use Jido.Agent,
    name: "agent",
    plugins: [
      {BB.Jido.Plugin.Robot, %{robot: MyRobot}}
    ]
end
```

`BB.Jido.Plugin.Robot` is the integration point. Attaching it adds four
actions to the agent (`BB.Jido.Action.Command`, `.Reactor`, `.WaitForState`,
`.GetJointState`) and three default signal routes:

| Signal type | Action |
|---|---|
| `bb.command.execute` | `BB.Jido.Action.Command` |
| `bb.reactor.run` | `BB.Jido.Action.Reactor` |
| `bb.state.wait` | `BB.Jido.Action.WaitForState` |

The plugin also mounts a [`BB.Jido.PubSubBridge`](../how-to/bridge-additional-pubsub-topics.md)
under the agent so robot state-machine transitions arrive as signals.
We'll see that in [Tutorial 2](02-reacting-to-pubsub.md).

> **Want to do this by hand instead?** The four generated pieces — the
> dep, the Jido instance, the supervision tree entry, the agent module —
> are all small. If you prefer to write them yourself, the equivalent
> generators are `mix bb_jido.add_jido_instance` and
> `mix bb_jido.add_agent`. See the
> [scaffolding how-to](../how-to/scaffold-with-igniter.md).

## Step 2: Make sure the robot starts in simulation

Open `lib/my_app/application.ex` and pass `simulation: :kinematic` to your
robot's child spec so you can run without hardware while learning:

```elixir
children = [
  {MyRobot, simulation: :kinematic},
  {Jido, [name: MyApp.Jido]}
]
```

(You can also use `mix bb.add_robot --robot MyRobot` if the robot module
doesn't yet exist.)

## Step 3: Start an agent and send it a signal

Open `iex -S mix`. The robot and Jido instance start automatically. Spawn
an agent:

```elixir
iex> {:ok, pid} = Jido.start_agent(MyApp.Jido, MyRobot.Agent, id: "main")
{:ok, #PID<0.500.0>}
```

The agent is now running. Robots start in `:disarmed`, so before we ask
the agent to do real work we'll arm the robot — using the agent:

```elixir
iex> arm_signal =
...>   Jido.Signal.new!(
...>     "bb.command.execute",
...>     %{robot: MyRobot, command: :arm, goal: %{}}
...>   )
iex> Jido.AgentServer.cast(pid, arm_signal)
:ok
```

`Jido.AgentServer.cast/2` enqueues the signal. The router matches
`bb.command.execute` to `BB.Jido.Action.Command`, which calls
`MyRobot.arm(%{})` and awaits the result via `BB.Command.await/2`. After
a moment, the robot will be `:armed` and the action will have returned
`{:ok, %{outcome: :armed, ...}}`. You can verify:

```elixir
iex> BB.Robot.Runtime.state(MyRobot)
:idle
```

> **Why `:idle` and not `:armed`?** Robots have two independent states: the
> safety state (`:armed`/`:disarmed`) and the operational state
> (`:idle`/`:executing`). `Runtime.state/1` returns the operational one when
> safety is `:armed`. See [Commands and State Machine](https://hexdocs.pm/bb/05-commands.html).

## Step 4: Run any robot command

Once armed, you can execute any command in the same way. If your robot
declares a `:home` command:

```elixir
iex> Jido.AgentServer.cast(
...>   pid,
...>   Jido.Signal.new!(
...>     "bb.command.execute",
...>     %{robot: MyRobot, command: :home, goal: %{}}
...>   )
...> )
:ok
```

## Step 5: Synchronous calls

`cast/2` is fire-and-forget. If you want the result, use `call/3` instead:

```elixir
iex> {:ok, agent} =
...>   Jido.AgentServer.call(
...>     pid,
...>     Jido.Signal.new!(
...>       "bb.command.execute",
...>       %{robot: MyRobot, command: :home, goal: %{}}
...>     )
...>   )
```

The return is the updated agent struct; the action's `{:ok, result}` is
recorded in `agent.result`.

## What you've built

```
Application
├── MyRobot                            # your robot + its supervision tree
└── Jido (name: MyApp.Jido)
    └── MyRobot.Agent (id: "main")
        ├── BB.Jido.PubSubBridge       # mounted by the plugin
        └── signal router → actions    # bb.command.execute, …
```

The agent is a single process; the bridge is a sibling under the agent's
own children. Crashes in the bridge restart the bridge only.

## Where next

- [Reacting to PubSub](02-reacting-to-pubsub.md) — read events into the
  agent and react to them.
- [Running Workflows](03-running-workflows.md) — invoke a `bb_reactor`
  workflow as a single Jido action.
- [Layered architecture](../topics/layered-architecture.md) — why the agent
  sits above `bb_reactor` rather than replacing it.
- [Scaffolding with Igniter](../how-to/scaffold-with-igniter.md) — all
  four generator tasks.
