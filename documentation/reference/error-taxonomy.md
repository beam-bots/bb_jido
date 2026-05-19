<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Error Taxonomy

`bb_jido` actions return errors as `{:error, reason}` tuples. The
`reason` follows a small, stable set of tags so application code can
pattern-match without inspecting strings.

## Action errors

| Error | When | Returned by |
|---|---|---|
| `:safety_disarmed` | Command process exited with `:disarmed` (robot was disarmed mid-flight). | `BB.Jido.Action.Command` |
| `{:command_failed, reason}` | Any other command failure: command callback returned an error, exited unexpectedly, timed out, or `apply(robot, command, [goal])` itself failed. | `BB.Jido.Action.Command` |
| `{:reactor_failed, errors}` | Reactor returned `{:error, errors}` — at least one step failed and any defined compensation has already run. | `BB.Jido.Action.Reactor` |
| `{:reactor_halted, halted}` | Reactor returned `{:halted, halted}` — execution was paused (e.g. a step asked to halt). `halted` is the halted reactor struct. | `BB.Jido.Action.Reactor` |
| `:timeout` | `WaitForState` ran out of time before the target state was reached. | `BB.Jido.Action.WaitForState` |
| `{:subscribe_failed, reason}` | `BB.PubSub.subscribe/3` refused the subscription. | `BB.Jido.Action.WaitForState` |

## `BB.Jido.Action.SafetyAware` guard errors

| Error | Meaning |
|---|---|
| `{:safety_not_armed, state}` | The robot's safety state is `state` (one of `:disarmed`, `:disarming`, `:error`). The wrapped `run/2` was not invoked. |
| `:robot_not_specified` | Neither `params[:robot]` nor `context[:robot]` provided a robot module. |

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
