<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Plugin & Action Configuration Reference

## `BB.Jido.Plugin.Robot`

Attach to an agent's `plugins:` list with a per-agent config map.

```elixir
use Jido.Agent,
  name: "my_robot",
  plugins: [{BB.Jido.Plugin.Robot, %{robot: MyRobot}}]
```

### Config

| Key | Type | Required | Default | Description |
|---|---|---|---|---|
| `:robot` | `module()` | yes | — | The Beam Bots robot module |
| `:topics` | `[[atom()]]` | no | `[[:state_machine]]` | PubSub paths the bridge subscribes to |
| `:message_types` | `[module()]` | no | `[]` | Payload modules to filter on (`[]` = no filter) |
| `:throttle_ms` | `pos_integer()` | no | `nil` | Minimum interval between same-type signals |

### State

The plugin owns the agent's `:robot` state slice:

| Field | Type | Initial | Description |
|---|---|---|---|
| `:robot` | `module()` | the configured robot | Mirror of `config[:robot]` for convenience |
| `:safety_state` | `atom()` | `:unknown` | Cached safety state; updated when a `bb.state.transition` signal arrives |
| `:last_joint_state` | `map()` | `%{}` | Reserved for joint-state caching (not yet populated) |

### Built-in actions

| Action | Default route | Purpose |
|---|---|---|
| `BB.Jido.Action.Command` | `bb.command.execute` | Run a BB command via `BB.Command.await/2` |
| `BB.Jido.Action.Reactor` | `bb.reactor.run` | Run a `bb_reactor` workflow with `context.private.bb_robot` set |
| `BB.Jido.Action.WaitForState` | `bb.state.wait` | Block until robot reaches a target state |
| `BB.Jido.Action.GetJointState` | (none — call directly) | Read positions/velocities from `BB.Robot.Runtime` |

### Child processes

The plugin's `child_spec/1` returns one supervised child:

| Child | Type | `:id` | Restart |
|---|---|---|---|
| `BB.Jido.PubSubBridge` | `:worker` | `{BB.Jido.Plugin.Robot, :pub_sub_bridge, robot}` | `:transient` |

## `BB.Jido.PubSubBridge` options

The bridge is mounted by the plugin, but you can also start it directly
under a different supervisor if you want PubSub-to-Signal forwarding
without an agent.

```elixir
{:ok, bridge} =
  BB.Jido.PubSubBridge.start_link(
    robot: MyRobot,
    agent: agent_pid_or_name,
    topics: [[:state_machine]]
  )
```

| Option | Type | Required | Default | Description |
|---|---|---|---|---|
| `:robot` | `module()` | yes | — | Robot module to subscribe against |
| `:agent` | `GenServer.server()` | yes | — | Where to cast signals (pid, registered name, via-tuple) |
| `:topics` | `[[atom()]]` | no | `[[:state_machine]]` | PubSub paths |
| `:message_types` | `[module()]` | no | `[]` | Payload filter |
| `:throttle_ms` | `pos_integer()` | no | `nil` | Same-type throttle in ms |
| `:name` | `GenServer.name()` | no | — | Standard `GenServer.start_link` option |

All standard `GenServer.start_link` options (`:timeout`, `:debug`,
`:spawn_opt`, `:hibernate_after`) are also accepted.

## Action schemas

Each action's `:schema` is documented below using `[type:, required:, default:]`
notation matching the [NimbleOptions] format that `Jido.Action` accepts.

[NimbleOptions]: https://hexdocs.pm/nimble_options/

### `BB.Jido.Action.Command`

| Param | Type | Required | Default |
|---|---|---|---|
| `:robot` | `:atom` | ✓ | — |
| `:command` | `:atom` | ✓ | — |
| `:goal` | `:map` |  | `%{}` |
| `:timeout` | `:pos_integer` |  | `30_000` |

### `BB.Jido.Action.Reactor`

| Param | Type | Required | Default |
|---|---|---|---|
| `:robot` | `:atom` | ✓ | — |
| `:reactor` | `:atom` | ✓ | — |
| `:inputs` | `:map` |  | `%{}` |

### `BB.Jido.Action.WaitForState`

| Param | Type | Required | Default |
|---|---|---|---|
| `:robot` | `:atom` | ✓ | — |
| `:target` | `:atom` | ✓ | — |
| `:timeout` | `:pos_integer` |  | `30_000` |

### `BB.Jido.Action.GetJointState`

| Param | Type | Required | Default |
|---|---|---|---|
| `:robot` | `:atom` | ✓ | — |
