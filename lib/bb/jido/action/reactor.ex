# SPDX-FileCopyrightText: 2026 James Harton
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
  """

  use Jido.Action,
    name: "bb_reactor",
    description: "Execute a Beam Bots reactor workflow",
    schema: [
      robot: [type: :atom, required: true, doc: "Robot module"],
      reactor: [type: :atom, required: true, doc: "Reactor module"],
      inputs: [type: :map, default: %{}, doc: "Reactor inputs"]
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
            {:ok, %{robot: robot, reactor: reactor, result: result}}

          {:ok, result, _reactor_struct} ->
            {:ok, %{robot: robot, reactor: reactor, result: result}}

          {:halted, halted} ->
            {:error, {:reactor_halted, halted}}

          {:error, errors} ->
            {:error, {:reactor_failed, errors}}
        end
      end
    )
  end
end
