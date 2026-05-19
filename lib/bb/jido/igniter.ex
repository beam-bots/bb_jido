# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule BB.Jido.Igniter do
    @moduledoc """
    Helpers for `bb_jido`'s Igniter installer and generator tasks.

    Only available when `:igniter` is loaded.
    """

    alias Igniter.Project.Module, as: IgniterModule

    @doc """
    Returns the Jido instance module to operate on.

    Resolution order:

      1. The `--jido-instance` option from `igniter.args.options` (parsed
         module name).
      2. `{AppPrefix}.Jido` (e.g. `MyApp.Jido`).

    Add `jido_instance: :string` to your task's schema to support the flag.
    """
    @spec jido_instance_module(Igniter.t()) :: module()
    def jido_instance_module(igniter) do
      case Keyword.get(igniter.args.options, :jido_instance) do
        nil -> IgniterModule.module_name(igniter, "Jido")
        name -> IgniterModule.parse(name)
      end
    end

    @doc """
    Returns the agent module to operate on.

    Resolution order:

      1. The `--agent` option from `igniter.args.options` (parsed module
         name).
      2. `{robot_module}.Agent` if a robot module is supplied.
      3. `{AppPrefix}.Agent` as the last-resort default.

    Add `agent: :string` to your task's schema to support the flag.
    """
    @spec agent_module(Igniter.t(), module() | nil) :: module()
    def agent_module(igniter, robot_module \\ nil) do
      case Keyword.get(igniter.args.options, :agent) do
        nil when is_atom(robot_module) and not is_nil(robot_module) ->
          Module.concat(robot_module, "Agent")

        nil ->
          IgniterModule.module_name(igniter, "Agent")

        name ->
          IgniterModule.parse(name)
      end
    end
  end
end
