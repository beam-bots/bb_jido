<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Signals and PubSub

BB and Jido both have an event mechanism. BB has `BB.PubSub` — a
hierarchical-path message broker. Jido has signals — CloudEvents-flavoured
structs routed by an agent's signal router. `bb_jido` translates the
former into the latter. This page explains why, and what the design
choices buy you.

## Two systems, two vocabularies

`BB.PubSub` delivers Erlang messages with a uniform shape:

```elixir
{:bb, source_path, %BB.Message{payload: payload, robot: robot, ...}}
```

- The **source path** is a list of atoms — the publisher's full path
  (e.g. `[:sensor, :joint_state]`).
- The **payload** is a domain struct: `BB.StateMachine.Transition`,
  `BB.Safety.HardwareError`, sensor-specific structs, etc.

Jido signals are [CloudEvents]: a `:type` string plus a payload in `:data`,
plus standard envelope fields (`:source`, `:id`, `:specversion`, `:time`).
The agent's router dispatches by type-string pattern.

[CloudEvents]: https://cloudevents.io/

These two vocabularies don't translate one-to-one. PubSub is a *transport*
— it doesn't care what the payload means. Signals are a *protocol* — the
type carries semantic meaning.

## Why a bridge instead of a Jido Sensor?

Jido provides a `Jido.Sensor` abstraction for ingesting external events.
On paper that's the obvious place to hook PubSub in. In practice it adds
a layer of indirection that buys nothing:

- The sensor runtime expects events to be *injected* via
  `Jido.Sensor.Runtime.event/2`. But BB already delivers events as Erlang
  messages.
- We'd be writing a sensor that does nothing but receive a message and
  forward it. The bridge code is the same; the sensor wrapper is dead
  weight.

So `BB.Jido.PubSubBridge` is a plain `GenServer` that subscribes to
`BB.PubSub` and casts forward via `Jido.AgentServer.cast/2`. A future
sensor wrapper remains possible if a future Jido feature genuinely needs
one — it's not a one-way door.

## Canonical signal types

The bridge produces three families of signal type:

| When | Type | Why |
|---|---|---|
| `%BB.StateMachine.Transition{}` payload | `bb.state.transition` | Specialised — agents almost always want to react to transitions specifically. |
| `%BB.Safety.HardwareError{}` payload | `bb.safety.error` | Specialised — safety errors deserve their own type. |
| Anything else | `bb.pubsub.<dotted source path>` | Generic — preserves the path information but no semantic claim. |

The specialised types are *stable*. Even if a future BB version changes
where state transitions are published, the signal type stays
`bb.state.transition`. The generic `bb.pubsub.*` type is necessarily
coupled to the path layout — it's a fallback, not a contract.

The signal `:source` is `/bb/<robot module>`, following CloudEvents'
URI-like source convention. Traceability stays sane when multiple robots'
events end up on the same downstream bus.

## Filtering happens before the agent

Three places to filter, from cheapest to most expensive:

1. **Topic allowlist** — only subscribe to paths the agent needs. Filters
   inside BB's registry; non-matching topics never trigger any work.
2. **Message-type filter** — pass `:message_types` so the registry only
   delivers matching payloads.
3. **Bridge-side throttle** — `:throttle_ms` drops repeat signals of the
   same type within the window. Signals are still constructed; they're
   just not cast forward.

Filtering at the agent's mailbox is the wrong place. By the time the
agent receives the cast, it's already paid the signal-construction cost,
and the mailbox queue may already be backed up. The bridge owns the
discipline.

## Filtering happens *outside* PubSub for content

The bridge can't peek inside a payload — that would couple it to every
payload type in BB. If you need content-based filtering ("only IMU
readings from the `:link3` frame"), do it in your action:

```elixir
def run(%{message: %BB.Message{} = message} = params, _ctx) do
  case message do
    %BB.Message{frame_id: :link3, payload: %BB.Message.Sensor.Imu{} = imu} ->
      handle_imu(params.robot, imu)

    _ ->
      {:ok, %{ignored: true}}
  end
end
```

This keeps the bridge a thin pipe and pushes domain knowledge into the
agent's action code, where it belongs.

## See also

- [Bridge additional PubSub topics](../how-to/bridge-additional-pubsub-topics.md)
  — the operational steps.
- [Signal types reference](../reference/signal-types.md) — full table of
  what gets emitted.
- BB's [PubSub documentation](https://hexdocs.pm/bb/pubsub-system.html).
