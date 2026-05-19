# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbJido.AddAgent do
    @shortdoc "Scaffolds a Jido agent that controls a BB robot"
    @moduledoc """
    #{@shortdoc}

    Creates a new module that `use`s `Jido.Agent` and attaches
    `BB.Jido.Plugin.Robot` for the given robot.

    Once generated, start the agent at runtime with:

        Jido.start_agent(MyApp.Jido, MyRobot.Agent, id: "main")

    ## Example

    ```bash
    mix bb_jido.add_agent --robot MyApp.Robot
    mix bb_jido.add_agent --robot MyApp.Robot --agent MyApp.MainAgent
    mix bb_jido.add_agent --robot MyApp.Robot --name main_robot
    ```

    ## Options

    * `--robot` - The robot module the agent will drive (defaults to
      `{AppPrefix}.Robot`).
    * `--agent` - The module name for the agent (defaults to
      `{robot_module}.Agent`).
    * `--name` - The Jido `name:` string for the agent (defaults to a
      snake_cased version of the agent module's last segment).
    """

    use Igniter.Mix.Task

    alias BB.Igniter, as: BBIgniter
    alias BB.Jido.Igniter, as: BBJidoIgniter
    alias Igniter.Project.Module

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [robot: :string, agent: :string, name: :string],
        aliases: [r: :robot, a: :agent, n: :name]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      robot_module = BBIgniter.robot_module(igniter)
      agent_module = BBJidoIgniter.agent_module(igniter, robot_module)
      agent_name = agent_name(igniter, agent_module)

      create_agent_module(igniter, agent_module, robot_module, agent_name)
    end

    defp create_agent_module(igniter, module, robot_module, agent_name) do
      case Module.module_exists(igniter, module) do
        {true, igniter} ->
          igniter

        {false, igniter} ->
          Module.create_module(igniter, module, """
          use Jido.Agent,
            name: #{inspect(agent_name)},
            plugins: [
              {BB.Jido.Plugin.Robot, %{robot: #{inspect(robot_module)}}}
            ]
          """)
      end
    end

    defp agent_name(igniter, agent_module) do
      case Keyword.get(igniter.args.options, :name) do
        nil ->
          agent_module
          |> Elixir.Module.split()
          |> List.last()
          |> Macro.underscore()

        name ->
          name
      end
    end
  end
else
  defmodule Mix.Tasks.BbJido.AddAgent do
    @shortdoc "Scaffolds a Jido agent that controls a BB robot"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_jido.add_agent task requires igniter.

          mix deps.get
          mix bb_jido.add_agent --robot MyApp.Robot
      """)

      exit({:shutdown, 1})
    end
  end
end
