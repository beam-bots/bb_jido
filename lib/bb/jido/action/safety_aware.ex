# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.SafetyAware do
  @moduledoc """
  Mixin for actions that should refuse to run unless the robot's safety
  controller is `:armed`.

  ## Usage

      defmodule MyAction do
        use Jido.Action,
          name: "my_action",
          schema: [robot: [type: :atom, required: true]]

        use BB.Jido.Action.SafetyAware

        @impl Jido.Action
        def run(params, context) do
          # only reached when robot is :armed
          {:ok, %{...}}
        end
      end

  The robot module is looked up first in `params[:robot]`, then in
  `context[:robot]`. If the robot is not `:armed`, the action returns
  `{:error, {:safety_not_armed, state}}` without invoking `run/2`.
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile BB.Jido.Action.SafetyAware
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      defoverridable run: 2

      def run(params, context) do
        robot = Map.get(params, :robot) || Map.get(context, :robot)

        case robot && BB.Safety.state(robot) do
          :armed ->
            super(params, context)

          nil ->
            {:error, :robot_not_specified}

          other ->
            {:error, {:safety_not_armed, other}}
        end
      end
    end
  end
end
