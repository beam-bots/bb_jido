# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbJido.AddAction do
    @shortdoc "Scaffolds a Jido action module"
    @moduledoc """
    #{@shortdoc}

    Creates a new module that `use`s `Jido.Action`, with a starter schema and
    a `run/2` callback returning `{:ok, %{}}`.

    ## Examples

    ```bash
    mix bb_jido.add_action MyApp.Actions.PickObject
    mix bb_jido.add_action MyApp.Actions.MovePose --safety-aware
    mix bb_jido.add_action MyApp.Actions.Teleop --name teleop_step
    ```

    ## Arguments

    The first positional argument is the module name for the new action
    (required).

    ## Options

    * `--name` - The Jido `name:` string for the action (defaults to a
      snake_cased version of the module's last segment).
    * `--description` - The Jido `description:` string.
    * `--safety-aware` - Mix in `BB.Jido.Action.SafetyAware` so the action
      refuses to run unless `BB.Safety.state(robot) == :armed`. Adds a
      `:robot` field to the schema.
    """

    use Igniter.Mix.Task

    alias Igniter.Project.Module

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        positional: [:action_module],
        schema: [
          name: :string,
          description: :string,
          safety_aware: :boolean
        ],
        aliases: [n: :name, d: :description, s: :safety_aware]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      action_module = Module.parse(igniter.args.positional.action_module)
      action_name = action_name(igniter, action_module)
      description = Keyword.get(igniter.args.options, :description)
      safety_aware? = Keyword.get(igniter.args.options, :safety_aware, false)

      create_action_module(igniter, action_module, action_name, description, safety_aware?)
    end

    defp create_action_module(igniter, module, action_name, description, safety_aware?) do
      case Module.module_exists(igniter, module) do
        {true, igniter} ->
          igniter

        {false, igniter} ->
          Module.create_module(
            igniter,
            module,
            action_body(action_name, description, safety_aware?)
          )
      end
    end

    defp action_body(action_name, description, safety_aware?) do
      """
      use Jido.Action,
        name: #{inspect(action_name)},#{description_line(description)}
        schema: #{schema_literal(safety_aware?)}
      #{safety_use_line(safety_aware?)}
      @impl Jido.Action
      def run(#{run_params(safety_aware?)}, _context) do
        {:ok, %{}}
      end
      """
    end

    defp description_line(nil), do: ""
    defp description_line(text), do: "\n  description: #{inspect(text)},"

    defp schema_literal(true) do
      """
      [
          robot: [type: :atom, required: true, doc: "Robot module"]
        ]\
      """
    end

    defp schema_literal(false), do: "[]"

    defp safety_use_line(true), do: "\nuse BB.Jido.Action.SafetyAware\n"
    defp safety_use_line(false), do: ""

    defp run_params(true), do: "%{robot: _robot} = _params"
    defp run_params(false), do: "_params"

    defp action_name(igniter, action_module) do
      case Keyword.get(igniter.args.options, :name) do
        nil ->
          action_module
          |> Elixir.Module.split()
          |> List.last()
          |> Macro.underscore()

        name ->
          name
      end
    end
  end
else
  defmodule Mix.Tasks.BbJido.AddAction do
    @shortdoc "Scaffolds a Jido action module"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_jido.add_action task requires igniter.

          mix deps.get
          mix bb_jido.add_action MyApp.Actions.MyAction
      """)

      exit({:shutdown, 1})
    end
  end
end
