# SPDX-FileCopyrightText: 2026 James Harton
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

  ## Configuration

  Plugin config (passed via `{BB.Jido.Plugin.Robot, %{...}}` when attaching
  to an agent):

  - `:robot` — robot module (required).
  - `:topics` — list of `BB.PubSub` paths to bridge (default
    `[[:state_machine]]`; replaces the default rather than adding to it).
  - `:message_types` — payload modules to filter on at subscribe time
    (default `[]`, meaning no filter).
  - `:throttle_ms` — optional per-signal-type throttle in milliseconds.

  Bridged topics beyond the defaults need matching signal routes on the
  agent (or plugin) — signals without a route are reported as routing
  errors through the agent's error policy.

  ## Example

      defmodule MyRobot.Agent do
        use Jido.Agent,
          name: "my_robot",
          plugins: [{BB.Jido.Plugin.Robot, %{robot: MyRobot}}]
      end
  """

  # Plugin name is `bb` so that Jido v2's plugin-route prefixing yields
  # the canonical user-facing signal types: a route declared here as
  # `command.execute` ends up as `bb.command.execute` after prefixing.
  use Jido.Plugin,
    name: "bb",
    state_key: :robot,
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

  @impl Jido.Plugin
  def mount(_agent, config) do
    case Map.fetch(config, :robot) do
      {:ok, robot} when is_atom(robot) ->
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

  defp default_topics, do: [[:state_machine]]

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
