<!--
SPDX-FileCopyrightText: 2026 James Harton

SPDX-License-Identifier: Apache-2.0
-->

# The Layered Architecture

`bb_jido` doesn't replace either `bb` or `bb_reactor`. It sits *above*
them. Understanding the three layers — and what belongs in which —
prevents most of the structural confusion teams encounter when first
introducing agents.

## The three layers

```
┌─────────────────────────────────────────────────┐
│  Jido Agent                                     │  ← decide what to do
│  - Receives signals (PubSub events, user input) │
│  - Routes them to actions                       │
│  - Decides which workflow or command to invoke  │
├─────────────────────────────────────────────────┤
│  bb_reactor Workflows                           │  ← how to do it
│  PickAndPlace, Calibrate, ReturnHome            │
│  - Declared sequences with compensation         │
│  - Compile-time validated                       │
├─────────────────────────────────────────────────┤
│  BB Commands                                    │  ← do it
│  move_to_pose, close_gripper, home, arm         │
│  - Direct hardware control                      │
└─────────────────────────────────────────────────┘
```

Each layer answers a different question:

| Layer | Question |
|---|---|
| Agent | "What should I do next to achieve this goal?" |
| Reactor | "How do I execute this multi-step task safely?" |
| Command | "How do I make the robot do this one thing?" |

## When to add an agent

You don't need an agent for every robot. Many production robots are happy
with `bb` plus `bb_reactor` — a reactor is run, it executes, returns a
result. Done.

Add an agent when the *decision* about which workflow to run is itself
non-trivial:

- The next action depends on perception ("if the part is here, pick it;
  if it's missing, search").
- The next action depends on coordination ("if robot A has the part,
  fetch from station B").
- The next action depends on input ("the operator just said 'home'").
- You need adaptive recovery ("the reactor failed — what now?").

Agents don't make sense if your decision logic is "always run reactor X
on a button press". A simple `MyRobot.Workflows.run/2` function is fine.

## Why the agent doesn't run steps directly

A Jido agent *could* dispatch BB commands one at a time, threading state
through with `Emit` directives. People sometimes try this because it
"looks like" a behaviour tree. Don't.

- **Compensation is hard to express.** Reactor's saga semantics roll back
  partial work on failure. An agent emitting individual commands has to
  reinvent that for every flow.
- **Validation is hard.** Reactor catches type and dependency mistakes at
  compile time. Agents are runtime-only.
- **The agent process becomes a hot path.** Every step blocks the agent
  mailbox. Even at modest rates this starves signal processing.

Use the agent to pick *which* reactor to run. Use the reactor to run it.

## Where state lives

| State | Owner | Where |
|---|---|---|
| Joint positions | BB runtime (ETS) | `BB.Robot.Runtime.positions/1` |
| Safety state | BB safety controller (ETS) | `BB.Safety.state/1` |
| Last transition (cached) | Robot plugin in agent state | `agent.state.robot.safety_state` |
| Reactor intermediate results | Reactor (ephemeral) | `context` per step |
| Application goals/queues | Your plugins | plugin state slice |

The agent is a poor place to store anything BB already tracks — ETS reads
are cheap and authoritative. The agent's plugin state is the right home
for things that are *agent-level*: a pending-task queue, an active goal,
the last command's outcome, etc.

## Multi-robot coordination

One agent per robot is the recommended default — supervision mirrors
robot identity, state stays local. Coordinator agents exist *alongside*,
not instead. They subscribe to robot-level signals (typically via
PubSub or your own bus) and emit task-assignment signals back.

```
Robot A agent ─▶ "robot.task.completed" ─▶ Coordinator ─▶ "robot.task.assigned" ─▶ Robot B agent
```

Keep the coordinator's per-robot state out of the per-robot plugins.

## Why a separate package?

The proposal calls this out: not every robot needs agents, Jido adds
weight, and agent patterns are still evolving. Keeping the agent layer in
its own package means you can upgrade or replace it without touching the
rest of the stack.

## See also

- [Signals and PubSub](signals-and-pubsub.md) — how events cross between
  layers.
- [Plugin lifecycle](plugin-lifecycle.md) — when `mount/2` and
  `child_spec/1` fire.
- The proposal — [`0009-bb-jido.md` in the proposals repo](https://github.com/beam-bots/proposals).
