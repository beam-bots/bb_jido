<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Signal Types Reference

All signal types emitted or routed by `bb_jido`. Type strings are stable
public API.

## Signals the bridge emits

These signals are produced by `BB.Jido.PubSubBridge` and cast into the
agent via `Jido.AgentServer.cast/2`.

### `bb.state.transition`

Robot state-machine transition. The plugin routes this type to
`BB.Jido.Action.UpdateSafetyState`, which caches safety transitions
(`to` in `:armed`, `:disarmed`, `:disarming`, `:error`) at
`agent.state.robot.safety_state`.

| Field | Value |
|---|---|
| `:type` | `"bb.state.transition"` |
| `:source` | `"/bb/<robot module>"` |
| `:data.robot` | robot module |
| `:data.path` | `[:state_machine]` |
| `:data.message` | `%BB.Message{payload: %BB.StateMachine.Transition{from: from, to: to}}` |

### `bb.safety.error`

Safety hardware error. The plugin routes this type to
`BB.Jido.Action.RecordSafetyError`, which stores the payload at
`agent.state.robot.last_safety_error`.

| Field | Value |
|---|---|
| `:type` | `"bb.safety.error"` |
| `:source` | `"/bb/<robot module>"` |
| `:data.robot` | robot module |
| `:data.path` | `[:safety, :error]` |
| `:data.message` | `%BB.Message{payload: %BB.Safety.HardwareError{path: path, error: error}}` |

### `bb.parameter.changed`

Robot parameter update. Published by BB on `[:param | path]` topics —
bridge one with `:topics` to receive these.

| Field | Value |
|---|---|
| `:type` | `"bb.parameter.changed"` |
| `:source` | `"/bb/<robot module>"` |
| `:data.robot` | robot module |
| `:data.path` | `[:param \| parameter_path]` |
| `:data.message` | `%BB.Message{payload: %BB.Parameter.Changed{path: path, old_value: old, new_value: new, source: source}}` |

### `bb.pubsub.<dotted source path>`

Generic envelope for any other PubSub event. The path component is the
publisher's full source path joined by `.` — so a publish on
`[:sensor, :joint_state]` yields type `bb.pubsub.sensor.joint_state`.

| Field | Value |
|---|---|
| `:type` | `"bb.pubsub.<path>"` |
| `:source` | `"/bb/<robot module>"` |
| `:data.robot` | robot module (or `message.robot` if unset on the bridge) |
| `:data.path` | the source path as a list of atoms |
| `:data.message` | the full `%BB.Message{}` |

## Signals routed by `BB.Jido.Plugin.Robot`

These signal types are intended for *application code* to send into the
agent. The plugin's `signal_routes:` dispatches them to actions.

### `bb.command.execute` -> `BB.Jido.Action.Command`

Execute a robot command.

Required `:data` keys:

| Key | Type | Description |
|---|---|---|
| `:robot` | `module()` | Robot module |
| `:command` | `atom()` | Command name |

Optional:

| Key | Type | Default |
|---|---|---|
| `:goal` | `map()` | `%{}` |
| `:timeout` | `pos_integer()` (ms) | `30_000` |

### `bb.reactor.run` -> `BB.Jido.Action.Reactor`

Run a `bb_reactor` workflow.

Required `:data` keys:

| Key | Type | Description |
|---|---|---|
| `:robot` | `module()` | Robot module |
| `:reactor` | `module()` | Reactor module |

Optional:

| Key | Type | Default |
|---|---|---|
| `:inputs` | `map()` | `%{}` |

### `bb.state.wait` -> `BB.Jido.Action.WaitForState`

Block the agent until the robot reaches a target state.

Required `:data` keys:

| Key | Type | Description |
|---|---|---|
| `:robot` | `module()` | Robot module |
| `:target` | `atom()` | Desired robot state |

Optional:

| Key | Type | Default |
|---|---|---|
| `:timeout` | `pos_integer()` (ms) | `30_000` |

## Custom signals

Anything outside the `bb.*` namespace is application-defined. Recommended
convention:

- `<app>.<domain>.<event>` for state changes (`my_robot.pick.completed`)
- `<app>.<domain>.<command>` for imperative requests (`my_robot.pick.start`)
- Avoid the `bb.*` prefix to keep BB-originating signals identifiable.

## Building a signal

```elixir
Jido.Signal.new!(
  "bb.command.execute",
  %{robot: MyRobot, command: :home, goal: %{}}
)
```

Or via the keyword/map form:

```elixir
Jido.Signal.new!(%{
  type: "bb.command.execute",
  source: "/my_app/teleop",
  data: %{robot: MyRobot, command: :home, goal: %{}}
})
```

`:id` and `:time` are generated for you. `:specversion` is set to
CloudEvents 1.0.2.
