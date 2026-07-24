# SPDX-FileCopyrightText: 2026 James Harton
# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Plugin.Robot do
  @moduledoc """
  Jido v2 plugin that gives an agent the ability to control a Beam Bots robot.

  Provides:

  - The standard robot-control actions: `BB.Jido.Action.Command`,
    `BB.Jido.Action.Reactor`, `BB.Jido.Action.WaitForState`, and
    `BB.Jido.Action.GetJointState`.
  - Default signal routes for the canonical `bb.*` signal types, including
    routes that keep the plugin state current: `bb.state.transition` is
    routed to `BB.Jido.Action.UpdateSafetyState` and `bb.safety.error` to
    `BB.Jido.Action.RecordSafetyError`.
  - Plugin-owned state under `agent.state.robot`: the configured `:robot`
    module, a cached `:safety_state` (updated by the routed
    `UpdateSafetyState` action whenever a safety transition arrives), the
    `:last_safety_error` (updated by `RecordSafetyError` when the
    `[:safety, :error]` topic is bridged), and `:last_joint_state` (updated
    whenever `GetJointState` runs).
  - A supervised `BB.Jido.PubSubBridge` mounted under the agent process that
    forwards BB PubSub events to the agent as Jido signals.
  - An optional fail-closed safety gate: actions listed in
    `:gated_actions` are refused before execution unless the robot's
    safety controller reports `:armed`.

  ## Configuration

  Plugin config (passed via `{BB.Jido.Plugin.Robot, %{...}}` when attaching
  to an agent) is validated against the plugin's `config_schema` when the
  agent is defined, so a missing, mistyped, or unrecognised option fails
  fast with a schema error rather than surfacing later at runtime:

  - `:robot` — robot module (required).
  - `:topics` — list of `BB.PubSub` paths to bridge (default
    `[[:state_machine]]`; replaces the default rather than adding to it).
  - `:message_types` — payload modules to filter on at subscribe time
    (default `[]`, meaning no filter).
  - `:throttle_ms` — optional per-signal-type throttle in milliseconds.
  - `:gated_actions` — list of action modules refused via
    `prepare_action/3` unless `BB.Safety.state/1` reports `:armed`
    (default `[]`). See below.

  Bridged topics beyond the defaults need matching signal routes on the
  agent (or plugin) — signals without a route are reported as routing
  errors through the agent's error policy.

  ## Safety gating

  With `gated_actions: [BB.Jido.Action.Command, BB.Jido.Action.Reactor]`,
  any routed signal that resolves to one of those actions is refused with
  `{:error, {:safety_not_armed, state}}` *before* the action executes,
  using an authoritative `BB.Safety.state/1` read (fast ETS). This is the
  plugin-level counterpart to the per-action `BB.Jido.Action.SafetyAware`
  mixin: the mixin travels with the action module wherever it's used,
  while the gate is enforced centrally for signal-routed execution on this
  agent. The gate fails closed and cannot be bypassed by the routed
  action's own params: a gated action whose params name a robot other
  than the configured one is rejected with
  `{:error, {:robot_mismatch, details}}` rather than authorised against
  the wrong robot's safety state.

  The gate only sees signal-routed execution — direct `run/2` calls (e.g.
  reactor steps) bypass it, so keep using `SafetyAware` for actions that
  must be guarded everywhere.

  ## Example

      defmodule MyRobot.Agent do
        use Jido.Agent,
          name: "my_robot",
          plugins: [
            {BB.Jido.Plugin.Robot,
             %{robot: MyRobot, gated_actions: [BB.Jido.Action.Command]}}
          ]
      end

  The plugin is a singleton: one robot per agent, and `as:` aliasing is
  rejected at agent definition. To control several robots, run one agent
  per robot.
  """

  # Plugin name is `bb` so that Jido v2's plugin-route prefixing yields
  # the canonical user-facing signal types: a route declared here as
  # `command.execute` ends up as `bb.command.execute` after prefixing.
  use Jido.Plugin,
    name: "bb",
    description: "Beam Bots robot control and observation for Jido agents",
    category: "robotics",
    tags: ["beam-bots", "robotics"],
    vsn: Mix.Project.config()[:version],
    capabilities: [:robot_control, :robot_observation],
    # One robot plugin per agent: the bridge emits fixed `bb.*` signal
    # types and the state-caching actions write to the fixed `:robot`
    # slice, so an `as:`-aliased instance (state key :robot_left, route
    # prefix left.bb) would receive no bridged signals and write effects
    # to the wrong slice. Multi-robot agents need an alias-aware bridge
    # and state ops first.
    singleton: true,
    state_key: :robot,
    config_schema:
      Zoi.object(
        %{
          robot:
            Zoi.atom(description: "Beam Bots robot module")
            |> Zoi.refine({__MODULE__, :validate_robot_module, []}),
          topics:
            Zoi.list(Zoi.list(Zoi.atom()),
              description: "BB.PubSub paths to bridge (replaces the default)"
            )
            |> Zoi.default([[:state_machine]]),
          message_types:
            Zoi.list(Zoi.atom(),
              description: "Payload modules to filter on at subscribe time ([] = no filter)"
            )
            |> Zoi.default([]),
          throttle_ms:
            Zoi.integer(description: "Minimum interval between same-type signals, in ms")
            |> Zoi.min(1)
            |> Zoi.optional(),
          gated_actions:
            Zoi.list(Zoi.atom(),
              description: "Action modules refused via prepare_action/3 unless the robot is armed"
            )
            # A misspelt module atom would validate as an atom, never match
            # the real routed action, and silently leave it ungated.
            |> Zoi.refine({Jido.Plugin, :validate_plugin_actions, []})
            |> Zoi.default([])
        },
        # A typo'd key (e.g. `gated_action:`) must be a hard error, not a
        # silently dropped safety control.
        unrecognized_keys: :error
      ),
    actions: [
      BB.Jido.Action.Command,
      BB.Jido.Action.GetJointState,
      BB.Jido.Action.Reactor,
      BB.Jido.Action.RecordSafetyError,
      BB.Jido.Action.UpdateSafetyState,
      BB.Jido.Action.WaitForState
    ],
    signal_routes: [
      {"command.execute", BB.Jido.Action.Command},
      {"reactor.run", BB.Jido.Action.Reactor},
      {"safety.error", BB.Jido.Action.RecordSafetyError},
      {"state.transition", BB.Jido.Action.UpdateSafetyState},
      {"state.wait", BB.Jido.Action.WaitForState}
    ]

  alias BB.Jido.PubSubBridge

  @doc false
  @spec validate_robot_module(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_robot_module(robot, _opts \\ []) do
    if is_atom(robot) and not is_nil(robot) and Code.ensure_loaded?(robot) and
         function_exported?(robot, :spark_is, 0) and robot.spark_is() == BB do
      :ok
    else
      {:error, "expected a Beam Bots robot module (one that `use BB`), got: #{inspect(robot)}"}
    end
  end

  @impl Jido.Plugin
  def mount(_agent, config) do
    case Map.fetch(config, :robot) do
      {:ok, robot} when is_atom(robot) and not is_nil(robot) ->
        {:ok,
         %{
           robot: robot,
           safety_state: :unknown,
           last_safety_error: nil,
           last_joint_state: %{}
         }}

      _ ->
        {:error, "BB.Jido.Plugin.Robot requires :robot module in config"}
    end
  end

  @impl Jido.Plugin
  def child_spec(config) do
    agent_pid = self()
    robot = Map.fetch!(config, :robot)
    topics = Map.get(config, :topics, default_topics())
    message_types = Map.get(config, :message_types, [])
    throttle_ms = Map.get(config, :throttle_ms)

    bridge_opts =
      [
        robot: robot,
        agent: agent_pid,
        topics: topics,
        message_types: message_types
      ]
      |> maybe_put(:throttle_ms, throttle_ms)

    %{
      id: {__MODULE__, :pub_sub_bridge, robot},
      start: {PubSubBridge, :start_link, [bridge_opts]},
      restart: :transient,
      type: :worker
    }
  end

  @impl Jido.Plugin
  def prepare_action(_signal, action_arg, %{config: config}) do
    case Map.get(config, :gated_actions, []) do
      [] -> {:ok, %{}}
      gated -> gate(action_arg, gated, Map.fetch!(config, :robot))
    end
  end

  # Normalising through Jido's own Instruction.normalize/3 covers every
  # action-argument shape Jido accepts (module, 2/3/4-tuples, keyword or
  # map params, %Jido.Instruction{}, and lists thereof) — enumerating
  # shapes by hand here is how gated forms slip through. An argument Jido
  # itself cannot normalise could never execute, but the gate still fails
  # closed rather than guessing.
  defp gate(action_arg, gated, configured_robot) do
    case Jido.Instruction.normalize(action_arg) do
      {:ok, instructions} ->
        targets =
          for %Jido.Instruction{action: module, params: params} <- instructions,
              module in gated,
              do: {module, params}

        case targets do
          [] -> {:ok, %{}}
          targets -> authorize_targets(targets, configured_robot)
        end

      {:error, reason} ->
        {:error, {:ungateable_action_arg, reason}}
    end
  end

  # The gate authorizes THIS plugin's robot, so a gated action whose params
  # name a different robot must be rejected outright — authorizing the
  # configured robot would otherwise approve a command aimed at a robot
  # whose safety state was never checked.
  defp authorize_targets(targets, configured_robot) do
    case Enum.find(targets, &robot_mismatch?(&1, configured_robot)) do
      {module, params} ->
        {:error,
         {:robot_mismatch,
          %{configured: configured_robot, requested: params_robot(params), action: module}}}

      nil ->
        authorize_armed(configured_robot)
    end
  end

  defp robot_mismatch?({_module, params}, configured_robot) do
    case params_robot(params) do
      nil -> false
      robot -> robot != configured_robot
    end
  end

  defp params_robot(%{robot: robot}), do: robot
  defp params_robot(%{"robot" => robot}), do: robot
  defp params_robot(_params), do: nil

  defp authorize_armed(robot) do
    case BB.Safety.state(robot) do
      :armed -> {:ok, %{}}
      other -> {:error, {:safety_not_armed, other}}
    end
  end

  defp default_topics, do: [[:state_machine]]

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
