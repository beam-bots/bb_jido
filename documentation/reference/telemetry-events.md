<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Telemetry Events Reference

`bb_jido` emits three telemetry events. Two are `:telemetry.span/3`
spans (with `:start`, `:stop`, and `:exception` legs); one is a single
counter event.

## `[:bb_jido, :action, :command]`

Emitted for every invocation of `BB.Jido.Action.Command.run/2`.

### `[:bb_jido, :action, :command, :start]`

| Measurement | Type | Notes |
|---|---|---|
| `:system_time` | `integer()` | `:erlang.system_time` |
| `:monotonic_time` | `integer()` | |

| Metadata | Type | Notes |
|---|---|---|
| `:robot` | `module()` | |
| `:command` | `atom()` | |
| `:telemetry_span_context` | reference | provided by `:telemetry.span/3` |

### `[:bb_jido, :action, :command, :stop]`

| Measurement | Type |
|---|---|
| `:duration` | `integer()` (native time units) |
| `:monotonic_time` | `integer()` |

| Metadata | Type | Notes |
|---|---|---|
| `:robot` | `module()` | |
| `:command` | `atom()` | |
| `:result_tag` | `:ok \| :error \| :other` | tag of the action return |
| `:telemetry_span_context` | reference | |

### `[:bb_jido, :action, :command, :exception]`

Emitted only if the action's `run/2` raises rather than returns
`{:error, _}`. Standard `:telemetry.span/3` exception metadata applies.

## `[:bb_jido, :action, :reactor]`

Same shape as `:command`. Metadata uses `:reactor` instead of `:command`.

| Metadata | Type |
|---|---|
| `:robot` | `module()` |
| `:reactor` | `module()` |
| `:result_tag` | `:ok \| :error \| :other` (stop event only) |
| `:telemetry_span_context` | reference |

## `[:bb_jido, :signal]`

Emitted once per signal that the bridge forwards to an agent (i.e. after
throttling).

| Measurement | Type |
|---|---|
| `:count` | `1` |

| Metadata | Type |
|---|---|
| `:robot` | `module() \| nil` |
| `:type` | `String.t()` — the signal's type, e.g. `"bb.state.transition"` |

## Attaching handlers

```elixir
:telemetry.attach_many(
  "bb_jido-logger",
  [
    [:bb_jido, :action, :command, :stop],
    [:bb_jido, :action, :reactor, :stop],
    [:bb_jido, :signal]
  ],
  &MyApp.Logger.handle/4,
  nil
)
```

For Prometheus-style metrics, use `Telemetry.Metrics`:

```elixir
[
  counter("bb_jido.signal.count", tags: [:robot, :type]),
  distribution(
    "bb_jido.action.command.duration",
    unit: {:native, :millisecond},
    tags: [:robot, :command, :result_tag]
  ),
  distribution(
    "bb_jido.action.reactor.duration",
    unit: {:native, :millisecond},
    tags: [:robot, :reactor, :result_tag]
  )
]
```

## Spans you might wish for

`BB.Jido.Action.WaitForState` and `BB.Jido.Action.GetJointState` do not
currently emit spans. They're cheap (an ETS read for one, a receive loop
for the other) so the noise wasn't worth it. If you need them, wrap your
own action in a `:telemetry.span/3` call — actions compose cleanly.
