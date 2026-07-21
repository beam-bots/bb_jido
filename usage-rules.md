<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# BB.Jido Usage Rules

`bb_jido` layers the [Jido](https://hex.pm/packages/jido) v2 agent framework
over a [Beam Bots](https://hexdocs.pm/bb) robot: it exposes BB commands and
`bb_reactor` workflows as Jido actions and bridges `BB.PubSub` events into Jido
signals, so a Jido agent can observe a robot and drive it toward a goal. For BB
framework basics, see `bb`'s rules (`mix usage_rules.sync <file> bb:all`); for
Jido itself, see [its docs](https://hexdocs.pm/jido). This file covers only the
bridge.

## Core principles

1. **This is a Jido plugin, not a BB DSL component.** You attach
   `BB.Jido.Plugin.Robot` to a Jido agent — you never add anything to the
   robot's `topology`. The robot and the agent are separate supervision trees;
   the agent talks to the robot through BB's public API.
2. **Agents act by sending signals, which route to actions.** Actions go
   through the ordinary BB command system and state machine, so the safety
   contract still holds: a `:disarmed` robot ignores motion. Arm through the
   agent by executing the robot's `:arm` command — never poke `BB.Safety`
   directly (that skips the prearm checks).
3. **The bridge runs both ways.** Outbound: BB commands and reactors become
   Jido actions. Inbound: `BB.PubSub` events become Jido signals via a
   `BB.Jido.PubSubBridge` the plugin mounts under the agent. You don't wire the
   bridge yourself.

## Installing and wiring in

Igniter adds the dep, creates a Jido instance, wires it into your supervision
tree, and (with `--robot`) scaffolds an agent:

```bash
mix igniter.install bb_jido --robot MyRobot
```

That produces a Jido instance (`use Jido, otp_app: :my_app`, added to the
supervision tree as `{Jido, [name: MyApp.Jido]}`) and an agent that attaches the
plugin:

```elixir
defmodule MyRobot.Agent do
  use Jido.Agent,
    name: "agent",
    plugins: [
      {BB.Jido.Plugin.Robot, %{robot: MyRobot}}
    ]
end
```

Attaching the plugin adds four actions (`BB.Jido.Action.Command`, `.Reactor`,
`.WaitForState`, `.GetJointState`) and three signal routes: `bb.command.execute`,
`bb.reactor.run`, and `bb.state.wait`.

## Running an agent

Start the agent under the Jido instance, then cast signals at it. The robot
starts `:disarmed`, so arm it first via the command action:

```elixir
{:ok, pid} = Jido.start_agent(MyApp.Jido, MyRobot.Agent, id: "main")

:ok =
  Jido.AgentServer.cast(
    pid,
    Jido.Signal.new!(
      "bb.command.execute",
      %{robot: MyRobot, command: :arm, goal: %{}}
    )
  )
```

`cast/2` is fire-and-forget; use `Jido.AgentServer.call/2` when you need the
result (it returns the updated agent struct, with the action's result under
`agent.result`). Once armed, execute any declared command by name the same way.

## Plugin config

Passed in the `{BB.Jido.Plugin.Robot, %{...}}` map:

| Key | Default | Meaning |
|---|---|---|
| `:robot` | — (required) | The robot module |
| `:topics` | `[[:state_machine]]` | `BB.PubSub` paths the bridge subscribes to |
| `:message_types` | `[]` (no filter) | Payload modules to filter on at subscribe time |
| `:throttle_ms` | none | Per-signal-type throttle in milliseconds |

`bb.state.transition` signals update the plugin's cached `:safety_state`
automatically. Opt into higher-volume topics (e.g. `[:sensor, :joint_state]`)
via `:topics`, and pair them with `:throttle_ms` to avoid flooding the agent.

## Safety-aware custom actions

Gate an action that moves the robot with the `BB.Jido.Action.SafetyAware`
mixin. It looks up the robot in `params[:robot]` then `context[:robot]` and
returns `{:error, {:safety_not_armed, state}}` before `run/2` runs unless the
robot is `:armed`:

```elixir
defmodule MyRobot.Action.Reach do
  use Jido.Action, name: "reach", schema: [robot: [type: :atom, required: true]]
  use BB.Jido.Action.SafetyAware

  @impl Jido.Action
  def run(_params, _context), do: {:ok, %{}}
end
```

## Anti-patterns

- **Don't arm by calling `BB.Safety` from an action.** Execute the `:arm`
  command through `BB.Jido.Action.Command` (a `bb.command.execute` signal) so
  the robot's prearm checks run.
- **Don't hand-roll a PubSub-to-signal forwarder.** The plugin already mounts a
  `BB.Jido.PubSubBridge`; add topics via `:topics`, don't build a parallel one.
- **Don't run `BB.Jido.Action.WaitForState` inline for long waits.** It blocks
  the agent server while waiting; run it from a dedicated process or workflow.
- **Don't confuse the reactor context keys.** `BB.Jido.Action.Reactor` binds the
  robot under `context.private.bb_robot`; that is distinct from `bb_reactor`'s
  own `context.private.bb` struct.

## Further reading

- [bb_jido docs](https://hexdocs.pm/bb_jido) — tutorials, signal types, and the
  full error taxonomy
- [Jido docs](https://hexdocs.pm/jido) — agents, actions, plugins, and signals
- `bb`'s safety and command rules (`bb:safety-and-commands`) and
  [Commands and State Machine](https://hexdocs.pm/bb/05-commands.html)
