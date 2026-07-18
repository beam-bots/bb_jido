<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to bridge additional PubSub topics

By default `BB.Jido.Plugin.Robot` only subscribes its `PubSubBridge` to
`[:state_machine]`. This guide shows how to forward additional BB topics
into your agent.

## When to do this

Add a topic when an action or plugin in the agent needs to *react* to
something other than state-machine transitions — for example a sensor
reading, a safety error, or a parameter change.

## Pass `:topics` when attaching the plugin

```elixir
defmodule MyRobot.Agent do
  use Jido.Agent,
    name: "my_robot",
    plugins: [
      {BB.Jido.Plugin.Robot,
       %{
         robot: MyRobot,
         topics: [
           [:state_machine],
           [:safety, :error],
           [:sensor, :joint_state]
         ]
       }}
    ]
end
```

Each entry is a list of atoms — the same format that
`BB.PubSub.subscribe/3` accepts. The list *replaces* the default
(`[[:state_machine]]`) rather than adding to it, so include
`[:state_machine]` explicitly if you still want it.

## Restrict by payload type

Subscribing to a path delivers *every* payload published on that path or
its descendants. Restrict at the PubSub layer with `:message_types`:

```elixir
{BB.Jido.Plugin.Robot,
 %{
   robot: MyRobot,
   topics: [[:sensor]],
   message_types: [BB.Message.Sensor.JointState, BB.Message.Sensor.Imu]
 }}
```

The filter is per-bridge (one bridge per agent), so it applies to every
subscribed topic.

## Check the resulting signal types

Each forwarded message becomes a `Jido.Signal` with a stable type string:

| Payload module | Signal type |
|---|---|
| `BB.StateMachine.Transition` | `bb.state.transition` |
| `BB.Safety.HardwareError` | `bb.safety.error` |
| Anything else | `bb.pubsub.<dotted source path>` |

So a sensor publishing on `[:sensor, :force_torque]` becomes
`bb.pubsub.sensor.force_torque`. Subscribe an action to it via:

```elixir
signal_routes: [
  {"bb.pubsub.sensor.force_torque", MyRobot.Actions.HandleFT}
]
```

The signal carries the original `%BB.Message{}` in `signal.data.message`.

## See also

- [Reacting to PubSub](../tutorials/02-reacting-to-pubsub.md) — end-to-end
  walkthrough.
- [Throttle high-volume signals](throttle-high-volume-signals.md) — keep
  100Hz topics from drowning the agent.
- [Signal types reference](../reference/signal-types.md) — full type table.
