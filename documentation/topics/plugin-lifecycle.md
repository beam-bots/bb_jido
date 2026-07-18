<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# Plugin Lifecycle

This page traces what happens when you attach `BB.Jido.Plugin.Robot` to
an agent and start the agent. Understanding the order lets you reason
about where to put state, why `child_spec/1` can call `self()`, and how
the bridge stays scoped to the agent.

## Where the agent lives

```
Application supervisor
└── Jido (name: MyApp.Jido)            ← DynamicSupervisor
    └── Jido.AgentServer (id: "main")  ← started by Jido.start_agent/3
        └── BB.Jido.PubSubBridge       ← started by plugin child_spec/1
```

The Jido instance is a `DynamicSupervisor`. `Jido.start_agent/3` calls
`DynamicSupervisor.start_child/2`, which spawns a `Jido.AgentServer`
process. That `AgentServer` then runs the plugin lifecycle below.

## Phase 1: agent compile-time

When you write:

```elixir
use Jido.Agent,
  name: "my_robot",
  plugins: [{BB.Jido.Plugin.Robot, %{robot: MyRobot}}]
```

…Jido validates the plugin list at compile time and stores plugin specs
on the agent module. The robot module reference is captured in the spec
*as data*; nothing is started yet.

## Phase 2: `Jido.start_agent/3`

The `AgentServer` is spawned. Its `init/1` does two things relevant to
plugins:

1. Calls each plugin's `mount/2` to build the agent's initial state. This
   is **pure** — no processes, no side effects.
2. Schedules `handle_continue(:post_init, state)` for child startup.

`BB.Jido.Plugin.Robot.mount/2`:

```elixir
def mount(_agent, %{robot: robot}) do
  {:ok,
   %{robot: robot, safety_state: :unknown, last_joint_state: %{}}}
end
```

The map returned becomes `agent.state.robot` (because the plugin's
`state_key: :robot`). If `:robot` is missing from config, `mount/2`
returns `{:error, ...}` and the agent fails to start.

## Phase 3: `handle_continue(:post_init, ...)`

This is where children are started. Crucially, the work happens inside
the `AgentServer` process — so `self()` here is the agent's pid.

`Jido.AgentServer.start_plugin_children/1` walks the plugin specs and
calls each plugin's `child_spec/1`. For `BB.Jido.Plugin.Robot`:

```elixir
def child_spec(config) do
  agent_pid = self()        # ← captured at this moment
  # ...build PubSubBridge child spec with agent: agent_pid
end
```

This is the *point*: `child_spec/1` is called from the agent process, so
`self()` *is* the agent. We capture it once and pass it to the bridge's
`start_link/1` opts.

The returned spec is fed into `Supervisor.child_spec(...)`-style startup.
The bridge is now a monitored child of the `AgentServer`: if either
crashes, the supervision tree handles it.

## Phase 4: bridge `init/1`

The bridge subscribes to its configured topics:

```elixir
for topic <- topics do
  BB.PubSub.subscribe(robot, topic, message_types: message_types)
end
```

…and stashes the agent pid in its state. From now on:

```
BB.PubSub  ──[:bb, path, %BB.Message{}]──▶  Bridge
                                              │
                                              │ Jido.AgentServer.cast/2
                                              ▼
                                          AgentServer
```

The bridge sees every matching delivery, turns it into a signal, and
casts. The agent's router takes it from there.

## Phase 5: signal routing

When the bridge casts a signal to the agent:

1. Each plugin's `handle_signal/2` pre-routing hook fires in declaration
   order (`BB.Jido.Plugin.Robot` doesn't implement one).
2. The signal router matches the type against the plugin's
   `signal_routes:` and any other plugin's routes. The robot plugin routes
   `bb.state.transition` to `BB.Jido.Action.UpdateSafetyState` and
   `bb.safety.error` to `BB.Jido.Action.RecordSafetyError` — that's how
   the cached `safety_state` and `last_safety_error` stay current.
3. The matched action's `run/2` is invoked. Its result map is merged into
   agent state, and any `Jido.Agent.StateOp` effects (how the caching
   actions write the plugin's state slice) are applied.
4. Any returned directives (e.g. `Emit`) are dispatched.

## What this means in practice

- **Don't start processes in `mount/2`.** It's pure; failures there crash
  agent creation, not a restartable child.
- **Don't store the agent pid in plugin state.** It's not needed —
  actions get the agent via context. The bridge needs it only because
  it lives in a separate process.
- **Don't restart the agent to pick up new bridge config.** Stop and
  restart the agent (`Jido.stop_agent/2` then `Jido.start_agent/3`).
  The bridge restarts as part of that.

## See also

- [`BB.Jido.Plugin.Robot`](../reference/plugin-config.md) — config
  reference.
- [Layered architecture](layered-architecture.md) — where the agent sits
  relative to BB and bb_reactor.
- [Jido's plugin documentation](https://hexdocs.pm/jido/Jido.Plugin.html)
  — the full callback list (we use a small subset).
