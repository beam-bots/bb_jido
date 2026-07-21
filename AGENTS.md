<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

`bb_jido` gives a [Beam Bots](https://github.com/beam-bots/bb) robot autonomous,
goal-directed behaviour by layering the [Jido](https://hex.pm/packages/jido) v2
agent framework over it. Where `bb_reactor` answers "how do I execute this
workflow?", `bb_jido` answers "what should I do next to achieve this goal?": the
agent observes the world via `BB.PubSub` (bridged to Jido signals) and dispatches
BB commands or `bb_reactor` workflows in response.

`bb_reactor` is a soft dependency — only needed for `BB.Jido.Action.Reactor`.

## Architecture

```
Jido Agent  (observes via BB.PubSub→signals, routes signals→actions, emits directives)
   └─ bb_reactor workflows + BB commands
      (run via BB.Jido.Action.Reactor / BB.Jido.Action.Command)
```

### Key modules (`lib/bb/jido/`)

| Module | Purpose |
|---|---|
| `BB.Jido.Plugin.Robot` (`plugin/robot.ex`) | Jido v2 plugin attached to an agent — adds robot state, the standard actions, default `bb.*` signal routes, and a supervised `PubSubBridge`. Config (Zoi-validated): `:robot` (required), `:topics` (default `[[:state_machine]]`), `:message_types`, `:throttle_ms`, `:gated_actions` (fail-closed armed-only gate via `prepare_action/3`). |
| `BB.Jido.Action.Command` (`action/command.ex`) | Run a BB command — `apply(robot, command, [goal])` then `BB.Command.await/2`. |
| `BB.Jido.Action.Reactor` (`action/reactor.ex`) | Run a `bb_reactor` workflow with the robot bound into `context.private.bb_robot`. |
| `BB.Jido.Action.WaitForState` (`action/wait_for_state.ex`) | Wait for the robot state machine to reach a target state. |
| `BB.Jido.Action.GetJointState` (`action/get_joint_state.ex`) | Read current joint positions/velocities. |
| `BB.Jido.Action.SafetyAware` (`action/safety_aware.ex`) | Mixin aborting an action with `{:safety_not_armed, state}` unless armed. |
| `BB.Jido.Action.UpdateSafetyState` (`action/update_safety_state.ex`) | Routed from `bb.state.transition`; caches safety transitions at `agent.state.robot.safety_state` via a `StateOp`. |
| `BB.Jido.Action.RecordSafetyError` (`action/record_safety_error.ex`) | Routed from `bb.safety.error`; records the last `%BB.Safety.HardwareError{}` at `agent.state.robot.last_safety_error`. |
| `BB.Jido.PubSubBridge` (`pub_sub_bridge.ex`) | GenServer forwarding `{:bb, path, %BB.Message{}}` into the agent as `Jido.Signal`s. |
| `BB.Jido.Signal` (`signal.ex`) | Canonical `BB.Message` → `Jido.Signal` mapping (CloudEvents `bb.*` namespace). |
| `BB.Jido.Telemetry` (`telemetry.ex`) | Telemetry spans for actions + per-signal counter. |

Igniter installers live in `lib/mix/tasks/` (`bb_jido.install`, `.add_agent`,
`.add_action`, `.add_jido_instance`).

## Build and Test Commands

```bash
mix check --no-retry    # Run all checks (compile, test, format, credo, dialyzer, reuse)
mix test                # Run tests
mix test path/to/test.exs:42  # Run single test at line
mix format              # Format code
mix credo --strict      # Linting
```

The project uses `ex_check` - always prefer `mix check --no-retry` over running individual tools.

## Key Patterns

### Signal naming

The `PubSubBridge` maps `BB.PubSub` events to a stable signal namespace:

- `bb.state.transition` — `[:state_machine]`, `%BB.StateMachine.Transition{}`
- `bb.safety.error` — `[:safety, :error]`, `%BB.Safety.HardwareError{}`
- `bb.parameter.changed` — `[:param | path]`, `%BB.Parameter.Changed{}`
- `bb.pubsub.<dotted.path>` — anything else

Source URI is `/bb/<robot module>`; payload, path, and robot live under
`signal.data`. The bridge subscribes to `[:state_machine]` only by default —
opt into higher-volume topics via the plugin's `:topics` (and `:message_types`
/ `:throttle_ms`).

### Error taxonomy

Actions return a consistent tagged-error set: `{:error, :safety_disarmed}`,
`{:error, {:command_failed, reason}}`, `{:error, {:reactor_failed, errors}}`,
`{:error, {:reactor_halted, reason}}`, `{:error, :timeout}`,
`{:error, {:subscribe_failed, reason}}`, `{:error, {:safety_not_armed, state}}`,
`{:error, :robot_not_specified}`. See
`documentation/reference/error-taxonomy.md` for when each fires.

### Reactor context

`BB.Jido.Action.Reactor` binds the robot into `context.private.bb_robot` for the
reactor run — distinct from `bb_reactor`'s own `context.private.bb` context
struct.

### Safety

Gate actions that move the robot with `BB.Jido.Action.SafetyAware`; the plugin
routes `bb.state.transition` signals to `BB.Jido.Action.UpdateSafetyState`,
which caches `:safety_state` in the plugin's state slice.

## Test Structure

ExUnit. Tests live under `test/bb/jido/`, mirroring `lib/`, plus
`test/mix/tasks/` for the igniter installers.
`test/support/test_robot.ex` provides `BB.Jido.TestRobot` (simulation mode) and
`BB.Jido.TestCommands.{Succeed,Fail,...}` for exercising the command/reactor
actions without hardware.

## Dependencies

- `bb ~> 0.16` — core framework (`BB.PubSub`, `BB.Command`, state machine, safety)
- `jido ~> 2.3` — agent framework (2.3 is required for the plugin `prepare_action/3` hook used by safety gating)
- `reactor ~> 1.0` — used by `BB.Jido.Action.Reactor` (soft dependency in practice)

Develop against a local `bb` checkout with `BB_VERSION=local` (expects `../bb`).

## When Making Changes

1. Run `mix check --no-retry` after any changes
