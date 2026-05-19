<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Reacting to PubSub

In [Tutorial 1](01-your-first-agent.md) you sent signals *into* an agent.
This tutorial shows the other direction: signals arriving *from* the robot.
Beam Bots publishes events on `BB.PubSub` (state-machine transitions,
sensor readings, safety errors); `bb_jido` bridges them into the agent as
`Jido.Signal`s so the agent can route them to actions.

## Prerequisites

- [Tutorial 1](01-your-first-agent.md).
- Familiarity with `BB.PubSub` (see [Sensors and PubSub](https://hexdocs.pm/bb/03-sensors-and-pubsub.html)).

## How the bridge works

When you attached `BB.Jido.Plugin.Robot` to your agent, the plugin mounted
a [`BB.Jido.PubSubBridge`](../reference/plugin-config.md#bb-jido-plugin-robot)
under the agent's supervision tree. The bridge:

1. Subscribes to BB topics on behalf of the agent (default:
   `[:state_machine]`).
2. Translates each `{:bb, path, %BB.Message{}}` delivery into a
   `Jido.Signal` using [`BB.Jido.Signal.from_pubsub/3`](../reference/signal-types.md).
3. Casts the signal into the agent via `Jido.AgentServer.cast/2`.

The signal's type follows the `bb.*` namespace:

| BB event | Signal type |
|---|---|
| State machine transitions | `bb.state.transition` |
| Safety hardware errors | `bb.safety.error` |
| Anything else | `bb.pubsub.<dotted.path>` |

## Step 1: Watch transitions arrive

Add a debug subscription in `iex` so you can see what the bridge would
push at the agent:

```elixir
iex> BB.PubSub.subscribe(MyRobot, [:state_machine])
{:ok, _}

iex> Jido.AgentServer.cast(
...>   pid,
...>   Jido.Signal.new!(
...>     "bb.command.execute",
...>     %{robot: MyRobot, command: :arm, goal: %{}}
...>   )
...> )
:ok

iex> flush()
{:bb, [:state_machine],
 %BB.Message{
   payload: %BB.StateMachine.Transition{from: :disarmed, to: :armed},
   ...
 }}
```

That same `{:bb, ...}` tuple is what `BB.Jido.PubSubBridge` receives.

## Step 2: Route the transition to your own action

Scaffold the action with the generator:

```bash
mix bb_jido.add_action MyRobot.OnArmed \\
  --description "Runs once the robot finishes arming"
```

That creates `lib/my_robot/on_armed.ex` with a stub `run/2`. Replace the
stub so it inspects the transition payload — Jido v2 passes `signal.data`
into the action as its params, so the schema declares fields that match
the shape `BB.Jido.Signal` produces:

```elixir
defmodule MyRobot.OnArmed do
  use Jido.Action,
    name: "on_armed",
    description: "Runs once the robot finishes arming",
    schema: [
      robot: [type: :atom, required: true],
      path: [type: {:list, :atom}, required: true],
      message: [type: :any, required: true]
    ]

  @impl Jido.Action
  def run(%{robot: robot, message: %BB.Message{payload: transition}}, _context) do
    IO.puts("#{inspect(robot)} transitioned #{transition.from} → #{transition.to}")
    {:ok, %{to: transition.to}}
  end
end
```

> **For Elixirists:** A Jido action is a behaviour module with a `run/2`
> callback. The `schema:` declares which params it accepts. When the
> router dispatches a signal to an action, `signal.data` is what gets
> passed as `params` — so the schema fields match the keys in `data`.

Now expose the action via a tiny plugin that adds the route. Plugins are
small enough that we don't ship a generator for them — write it by hand:

```elixir
defmodule MyRobot.WatcherPlugin do
  use Jido.Plugin,
    name: "watcher",
    state_key: :watcher,
    actions: [MyRobot.OnArmed],
    signal_routes: [
      {"bb.state.transition", MyRobot.OnArmed}
    ]
end
```

And attach it alongside the robot plugin. Edit the generated
`lib/my_robot/agent.ex` to add the watcher:

```elixir
defmodule MyRobot.Agent do
  use Jido.Agent,
    name: "agent",
    plugins: [
      {BB.Jido.Plugin.Robot, %{robot: MyRobot}},
      MyRobot.WatcherPlugin
    ]
end
```

Restart your iex session and arm the robot again — the bridge forwards the
transition, the router dispatches to `MyRobot.OnArmed`, and you'll see:

```
Robot transitioned disarmed → armed
```

## Step 3: Filter by *which* transition

Two `bb.state.transition` signals arrive when you cycle `arm` → `disarm`.
If you only care about one, pattern-match in your action:

```elixir
@impl Jido.Action
def run(%{message: %BB.Message{payload: payload}} = params, _context) do
  case payload do
    %BB.StateMachine.Transition{to: :armed} ->
      handle_armed(params.robot)

    %BB.StateMachine.Transition{to: :error} ->
      handle_error(params.robot)

    _other ->
      {:ok, %{ignored: true}}
  end
end
```

> **Why not route on a more specific type?** Today the bridge maps every
> transition to the same `bb.state.transition` type. Discriminating
> further lives in your action — that keeps the signal vocabulary stable.

## Step 4: Subscribe to additional topics

By default the plugin only subscribes to `[:state_machine]`. To also
forward, say, joint state messages, pass `:topics` when attaching:

```elixir
plugins: [
  {BB.Jido.Plugin.Robot,
   %{
     robot: MyRobot,
     topics: [[:state_machine], [:sensor, :joint_state]],
     message_types: [BB.StateMachine.Transition, BB.Sensor.JointState]
   }}
]
```

Now joint-state messages will arrive as `bb.pubsub.sensor.joint_state`
signals. Be careful: BB sensors can publish at 100Hz. The next tutorial
and the [Throttle high-volume signals](../how-to/throttle-high-volume-signals.md)
guide show how to keep the agent mailbox sane.

## What you've built

```
BB.PubSub                       Jido agent
─────────                       ──────────
state_machine ──▶ Bridge ──▶ bb.state.transition ──▶ MyRobot.OnArmed
                            ▶ (any other route)
```

The bridge is just plumbing. All decisions about what to do with an event
live in your actions and plugins.

## Where next

- [Running Workflows](03-running-workflows.md) — invoke a reactor when a
  signal arrives.
- [Signals and PubSub](../topics/signals-and-pubsub.md) — the design
  rationale for the bridge.
- [Throttle high-volume signals](../how-to/throttle-high-volume-signals.md)
  — keep the mailbox quiet under 100Hz sensors.
