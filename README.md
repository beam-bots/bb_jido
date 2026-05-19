<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

<img src="https://github.com/beam-bots/bb/blob/main/logos/beam_bots_logo.png?raw=true" alt="Beam Bots Logo" width="250" />

# BB.Jido

[![CI](https://github.com/beam-bots/bb_jido/actions/workflows/ci.yml/badge.svg)](https://github.com/beam-bots/bb_jido/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache--2.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![Hex version badge](https://img.shields.io/hexpm/v/bb_jido.svg)](https://hex.pm/packages/bb_jido)
[![REUSE status](https://api.reuse.software/badge/github.com/beam-bots/bb_jido)](https://api.reuse.software/info/github.com/beam-bots/bb_jido)

Autonomous agents for [Beam Bots](https://github.com/beam-bots/bb), built on
the [Jido](https://hex.pm/packages/jido) agent framework.

Where [`bb_reactor`](https://github.com/beam-bots/bb_reactor) answers "how do
I execute this workflow?", `bb_jido` lets you answer "what should I do next
to achieve this goal?" — your robot becomes a goal-directed agent that
observes the world via `BB.PubSub` and dispatches commands or workflows in
response.

## Layered architecture

```
┌─────────────────────────────────────────────────┐
│  Jido Agent                                     │
│  - Observes via BB.PubSub (bridged to signals)  │
│  - Routes signals to actions                    │
│  - Emits further signals as directives          │
├─────────────────────────────────────────────────┤
│  bb_reactor workflows  +  BB commands           │
│  (executed via BB.Jido.Action.Reactor and       │
│   BB.Jido.Action.Command)                       │
└─────────────────────────────────────────────────┘
```

## What's in the box

| Module | Purpose |
|---|---|
| `BB.Jido.Plugin.Robot` | Jido v2 plugin you attach to an agent — adds robot state, the standard actions, default `bb.*` signal routes, and the PubSub bridge |
| `BB.Jido.Action.Command` | Run a BB command (`apply(robot, command, [goal])`) and await its result |
| `BB.Jido.Action.Reactor` | Run a `bb_reactor` workflow with the robot bound into `context.private.bb_robot` |
| `BB.Jido.Action.WaitForState` | Wait for the robot state machine to enter a target state |
| `BB.Jido.Action.GetJointState` | Read current joint positions/velocities |
| `BB.Jido.Action.SafetyAware` | Mixin that aborts an action with `{:safety_not_armed, state}` unless the robot is armed |
| `BB.Jido.PubSubBridge` | GenServer that forwards `{:bb, path, %BB.Message{}}` messages into an agent as `Jido.Signal`s |
| `BB.Jido.Signal` | Canonical `BB.Message` → `Jido.Signal` mapping (CloudEvents `bb.*` namespace) |
| `BB.Jido.Telemetry` | Telemetry spans for actions and a per-signal counter |

## Installation

The fastest path is via [Igniter] — it adds the dep, generates a Jido
instance module, and wires it into your application supervision tree in
one command:

[Igniter]: https://hex.pm/packages/igniter

```bash
mix igniter.install bb_jido --robot MyApp.Robot
```

With `--robot`, it also scaffolds an agent module that attaches
`BB.Jido.Plugin.Robot` for that robot. Drop the flag to skip the agent
and add it later with `mix bb_jido.add_agent`.

`bb_reactor` is not a hard dependency. If you want to use
`BB.Jido.Action.Reactor`, add it the same way:

```bash
mix igniter.install bb_reactor
```

See [the scaffolding how-to](documentation/how-to/scaffold-with-igniter.md)
for the full list of generators.

## Quick start

After `mix igniter.install bb_jido --robot MyApp.Robot`, you'll have:

- `lib/my_app/jido.ex` — `use Jido, otp_app: :my_app`
- `lib/my_app/robot/agent.ex` — agent with the robot plugin attached
- `lib/my_app/application.ex` — children list gains `{Jido, [name: MyApp.Jido]}`

Start the agent and send it a signal:

```elixir
{:ok, pid} = Jido.start_agent(MyApp.Jido, MyApp.Robot.Agent, id: "main")

:ok =
  Jido.AgentServer.cast(
    pid,
    Jido.Signal.new!(
      "bb.command.execute",
      %{robot: MyApp.Robot, command: :home, goal: %{}}
    )
  )
```

## Signals

The PubSub bridge maps `BB.PubSub` events into Jido signals with a stable
naming scheme:

| Signal type | Source |
|---|---|
| `bb.state.transition` | `[:state_machine]` topic, `%BB.StateMachine.Transition{}` payloads |
| `bb.safety.error` | `[:safety, :error]` topic, `%BB.Safety.HardwareError{}` payloads |
| `bb.pubsub.<path>` | Anything else — dotted source path (e.g. `bb.pubsub.sensor.joint_state`) |

The source URI is `/bb/<robot module>` for traceability. Payload, path, and
robot are all available under `signal.data`.

By default the bridge only subscribes to `[:state_machine]`. Pass `:topics`
(and optionally `:message_types` or `:throttle_ms`) when attaching the
plugin to opt into higher-volume topics:

```elixir
plugins: [
  {BB.Jido.Plugin.Robot,
   %{robot: MyRobot,
     topics: [[:state_machine], [:sensor, :joint_state]],
     throttle_ms: 100}}
]
```

## Error taxonomy

Actions return a consistent tagged-error set:

- `{:error, :safety_disarmed}` — command exited because the robot was disarmed
- `{:error, {:command_failed, reason}}` — any other command failure
- `{:error, {:reactor_failed, errors}}` — reactor returned errors
- `{:error, {:reactor_halted, reason}}` — reactor was halted mid-flight
- `{:error, {:safety_not_armed, state}}` — `BB.Jido.Action.SafetyAware`
  guard tripped

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/bb_jido).
