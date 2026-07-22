<!--
SPDX-FileCopyrightText: 2026 James Harton
SPDX-FileCopyrightText: 2026 Holden Oullette

SPDX-License-Identifier: Apache-2.0
-->

# Error Taxonomy

`bb_jido` actions return errors as `{:error, reason}` tuples. The
`reason` follows a small, stable set of tags so application code can
pattern-match without inspecting strings.

## Action errors

| Error | When | Returned by |
|---|---|---|
| `:safety_disarmed` | The robot rejected the command because it was disarmed (`%BB.Error.State.NotAllowed{current_state: :disarmed}`), or the command surfaced `:disarmed` / `{:shutdown, :disarmed}` as its failure reason. | `BB.Jido.Action.Command` |
| `{:command_failed, reason}` | Any other command failure: the command's `result/1` returned an error, the process exited unexpectedly, or the await timed out. `reason` is wrapped exactly once — failures `BB.Command.await/2` already reports as `{:command_failed, reason}` (crash, `:timeout`, `:noproc`) keep their inner reason. | `BB.Jido.Action.Command` |
| `{:reactor_failed, errors}` | Reactor returned `{:error, errors}` — at least one step failed and any defined compensation has already run. | `BB.Jido.Action.Reactor` |
| `{:reactor_halted, halted}` | Reactor returned `{:halted, halted}` — execution was paused (e.g. a step asked to halt). `halted` is the halted reactor struct. | `BB.Jido.Action.Reactor` |
| `:timeout` | `WaitForState` ran out of time before the target state was reached. | `BB.Jido.Action.WaitForState` |
| `{:subscribe_failed, reason}` | `BB.PubSub.subscribe/3` refused the subscription. | `BB.Jido.Action.WaitForState` |
| `{:wait_failed, reason}` | The temporary subscriber process exited abnormally before the wait resolved. | `BB.Jido.Action.WaitForState` |

## `BB.Jido.Action.SafetyAware` guard errors

| Error | Meaning |
|---|---|
| `{:safety_not_armed, state}` | The robot's safety state is `state` (one of `:disarmed`, `:disarming`, `:error`). The wrapped `run/2` was not invoked. |
| `:robot_not_specified` | Neither `params[:robot]` nor `context[:robot]` provided a robot module. |

A disarm that happens *mid-flight* stops the command process, but awaiting
callers still receive whatever the command's `result/1` callback returns —
so a mid-flight disarm only maps to `:safety_disarmed` if the command's
`result/1` surfaces `:disarmed` (or `{:shutdown, :disarmed}`) as its error
reason. A raise inside the command function itself (e.g. an unknown
command name) propagates as an exception rather than a tagged tuple.

## Agent-routed execution

The tags above describe direct `run/2` calls (including reactor steps).
When an action runs via a signal route, `Jido.Exec` normalises error
tuples into `Jido.Action.Error` exception structs — the tag then appears
under the error's details rather than as a bare tuple. `Jido.Exec` also
enforces its own default 30s execution timeout independent of the
actions' `:timeout` params — and routed signals cannot override it,
because routed modules become `{module, signal.data}` with no
instruction opts (Jido route options only cover routing priority). For
longer commands, either raise the `:jido_action` `:default_timeout`
config or invoke the action through an explicit instruction whose
`:opts` set a `Jido.Exec` `:timeout`.

## Pattern-matching cheatsheet

```elixir
case BB.Jido.Action.Command.run(params, %{}) do
  {:ok, result} ->
    use_result(result)

  {:error, :safety_disarmed} ->
    alert_operator(:disarmed)

  {:error, {:command_failed, reason}} ->
    handle_failure(reason)
end
```

```elixir
case BB.Jido.Action.Reactor.run(params, %{}) do
  {:ok, %{result: result}} ->
    use_result(result)

  {:error, {:reactor_halted, _halted}} ->
    handle_halt()

  {:error, {:reactor_failed, errors}} ->
    handle_failure(errors)
end
```

## Why not structured `BB.Error` types?

BB itself uses Splode-backed error structs (`BB.Error.*`). `bb_jido`
deliberately uses tagged tuples instead because:

- Jido actions return `{:ok, _}` / `{:error, _}` tuples uniformly; that's
  the expected idiom.
- Agent signal handlers pattern-match on the *tag* most of the time. A
  tag is cheaper to match than a struct module.
- The underlying `reason` in `{:command_failed, reason}` is opaque — if
  the command callback returned a structured error, it's still there
  for inspection.

If your application standardises on `BB.Error` structs, wrap the action
boundary yourself.
