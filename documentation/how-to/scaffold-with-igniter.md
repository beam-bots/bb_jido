<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to scaffold bb_jido modules with Igniter

`bb_jido` ships four [Igniter] tasks for the boilerplate parts of wiring
agents up: declaring a Jido instance, adding it to the supervision tree,
creating an agent, and creating individual actions.

[Igniter]: https://hex.pm/packages/igniter

## One-shot install

`mix igniter.install bb_jido` runs `bb_jido.install`, which always
declares a Jido instance and (when `--robot` is given) scaffolds an
agent for it:

```bash
mix igniter.install bb_jido --robot MyApp.Robot
```

After that:

```
lib/my_app/jido.ex          ← use Jido, otp_app: :my_app
lib/my_app/robot/agent.ex   ← use Jido.Agent with BB.Jido.Plugin.Robot
lib/my_app/application.ex   ← children list gains {Jido, [name: MyApp.Jido]}
```

You're now one `Jido.start_agent/3` call away from a running agent.

## Individual tasks

### `mix bb_jido.add_jido_instance`

Creates the Jido instance module and adds `{Jido, name: <module>}` to the
application's supervision tree.

```bash
mix bb_jido.add_jido_instance
mix bb_jido.add_jido_instance --jido-instance MyApp.AgentRuntime
```

Idempotent — running it again is a no-op.

### `mix bb_jido.add_agent`

Creates an agent module that attaches `BB.Jido.Plugin.Robot` for the given
robot.

```bash
mix bb_jido.add_agent --robot MyApp.Robot
mix bb_jido.add_agent --robot MyApp.Robot --agent MyApp.MainAgent --name main_robot
```

| Flag | Default | Notes |
|---|---|---|
| `--robot` | `{AppPrefix}.Robot` | Robot module the agent drives |
| `--agent` | `{robot}.Agent` | Module name for the agent |
| `--name` | snake_cased last segment | Jido `name:` string |

The task does *not* start the agent — that's a runtime call:

```elixir
Jido.start_agent(MyApp.Jido, MyApp.Robot.Agent, id: "main")
```

### `mix bb_jido.add_action`

Scaffolds a Jido action with a `run/2` stub returning `{:ok, %{}}`.

```bash
mix bb_jido.add_action MyApp.Actions.Pick
mix bb_jido.add_action MyApp.Actions.MovePose --safety-aware
mix bb_jido.add_action MyApp.Actions.Teleop --name teleop_step \\
  --description "Drive the robot from a teleop joystick"
```

`--safety-aware` mixes in [`BB.Jido.Action.SafetyAware`](write-safety-aware-action.md)
and seeds the schema with a `:robot` field, so the action refuses to run
unless `BB.Safety.state(robot) == :armed`.

| Flag | Default | Notes |
|---|---|---|
| `--name` | snake_cased last segment | Jido `name:` string |
| `--description` | (none) | Jido `description:` string |
| `--safety-aware` | `false` | Add the safety guard mixin |

## What the tasks don't do

- They don't add **bb_reactor** as a dependency — `bb_jido` doesn't depend
  on it, and not every agent needs workflows.
- They don't patch existing `plugins:` lists or `signal_routes:` maps —
  once an agent exists, hand-editing is straightforward and avoids the
  fragility of source patching.
- They don't generate **example apps** or a **runnable simulation** — the
  inline tutorials cover that path.
