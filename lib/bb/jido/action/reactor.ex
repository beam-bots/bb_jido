# SPDX-FileCopyrightText: 2026 James Harton
# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.Reactor do
  @moduledoc """
  Jido action that runs a `bb_reactor` workflow.

  Enables agents to invoke structured reactor workflows as a single atomic
  operation. The robot module is injected into the reactor context under
  `context.private.bb_robot`, which is what `BB.Reactor.Middleware.Context`
  expects.

  ## Schema

  - `:robot` — the robot module (required).
  - `:reactor` — the reactor module (required).
  - `:inputs` — reactor input map (default `%{}`).

  ## Returns

  - `{:ok, %{reactor: ..., result: ...}}` on success.
  - `{:error, {:reactor_failed, errors}}` if the reactor returned errors.
  - `{:error, {:reactor_halted, halted}}` if the reactor halted (e.g. due to
    a safety event); `halted` is the halted reactor struct.

  When routed through an agent, the success map is merged into agent state
  by Jido's default strategy — result keys deliberately avoid the plugin's
  `:robot` state key.
  """

  use Jido.Action,
    name: "bb_reactor",
    description: "Execute a Beam Bots reactor workflow",
    category: "robotics",
    tags: ["beam-bots", "robot", "workflow"],
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"],
      reactor: [type: :atom, required: true, doc: "Reactor module"],
      inputs: [type: :map, default: %{}, doc: "Reactor inputs"]
    ],
    output_schema: [
      reactor: [type: :atom, doc: "The reactor that ran"],
      result: [type: :any, doc: "The reactor's return value"]
    ]

  alias BB.Jido.Telemetry

  @impl Jido.Action
  def run(%{robot: robot, reactor: reactor} = params, _context) do
    inputs = Map.get(params, :inputs, %{})
    context = %{private: %{bb_robot: robot}}

    Telemetry.span(
      [:bb_jido, :action, :reactor],
      %{robot: robot, reactor: reactor},
      fn ->
        case Reactor.run(reactor, inputs, context) do
          {:ok, result} ->
            {:ok, %{reactor: reactor, result: result}}

          {:ok, result, _reactor_struct} ->
            {:ok, %{reactor: reactor, result: result}}

          {:halted, halted} ->
            {:error, {:reactor_halted, halted}}

          {:error, errors} ->
            {:error, {:reactor_failed, errors}}
        end
      end
    )
  end
end
