<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# How to throttle high-volume signals

BB sensors can publish at 100Hz or higher. Forwarding every reading into
the agent will overflow its mailbox and starve other work. This guide
shows the layered mitigations available in `bb_jido`.

## Layer 1: don't subscribe in the first place

The cheapest filter is the one that never reaches the bridge. Only list
topics in the plugin config that the agent *actually* needs:

```elixir
{BB.Jido.Plugin.Robot,
 %{
   robot: MyRobot,
   topics: [[:state_machine]]   # joint state etc. NOT subscribed
 }}
```

## Layer 2: filter by message type at subscribe time

If you need a path but only certain payloads on it, pass `:message_types`.
The filter runs inside `BB.PubSub` before the message is sent at all:

```elixir
{BB.Jido.Plugin.Robot,
 %{
   robot: MyRobot,
   topics: [[:sensor]],
   message_types: [BB.Sensor.ForceTorque]
 }}
```

Now JointState publishes on `[:sensor, :joint_state]` won't reach the
bridge at all even though `[:sensor]` is subscribed.

## Layer 3: throttle in the bridge

For genuinely high-volume topics, set `:throttle_ms`. The bridge will drop
any signal of a type that was emitted less than `throttle_ms` milliseconds
ago:

```elixir
{BB.Jido.Plugin.Robot,
 %{
   robot: MyRobot,
   topics: [[:state_machine], [:sensor, :joint_state]],
   throttle_ms: 100
 }}
```

A 100Hz joint-state stream becomes a 10Hz signal stream. State-machine
transitions still pass through immediately because they have a different
signal type (`bb.state.transition` vs `bb.pubsub.sensor.joint_state`).

> **Important:** the throttle drops by *type*, not by content. A latest-
> value workflow is fine; a "we must see every reading" workflow is not.
> For that, subscribe directly to `BB.PubSub` outside the agent.

## Layer 4: don't put fast events in the agent at all

If an event is high-volume *and* doesn't affect agent decisions, keep it
out of the agent. The pattern:

- A separate `GenServer` subscribes to the high-volume topic.
- It maintains the current value and exposes it via `:ets` or a public
  API.
- The agent reads the value when it needs to (via an action that does a
  cheap lookup).

This is exactly the "last-known-state cache" the proposal recommends.
`BB.Jido.Action.GetJointState` is an instance of this pattern: it reads
positions from `BB.Robot.Runtime`'s ETS cache rather than waiting for a
PubSub message.

## See also

- [`BB.Jido.PubSubBridge`](../reference/plugin-config.md#pubsubbridge-options)
  — full option reference.
- [Signals and PubSub](../topics/signals-and-pubsub.md) — why throttling
  on the bridge side is preferable to backpressure at the mailbox.
