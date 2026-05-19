# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbJido.Install do
    @shortdoc "Installs bb_jido into a project"
    @moduledoc """
    #{@shortdoc}

    Always composes `bb_jido.add_jido_instance`, which creates a Jido
    instance module and wires it into the application supervision tree.

    If `--robot` is supplied, also composes `bb_jido.add_agent` to scaffold
    an agent module that drives that robot.

    ## Examples

    ```bash
    mix igniter.install bb_jido
    mix igniter.install bb_jido --robot MyApp.Robot
    mix igniter.install bb_jido --robot MyApp.Robot --jido-instance MyApp.AgentRuntime
    ```

    ## Options

    * `--robot` - If given, scaffolds an agent module for this robot.
    * `--agent` - The agent module name (passed to `bb_jido.add_agent`).
    * `--jido-instance` - The Jido instance module name (passed to
      `bb_jido.add_jido_instance`).
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        composes: ["bb_jido.add_jido_instance", "bb_jido.add_agent"],
        schema: [robot: :string, agent: :string, jido_instance: :string],
        aliases: [r: :robot, a: :agent, j: :jido_instance]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      igniter
      |> Igniter.compose_task("bb_jido.add_jido_instance", instance_argv(igniter))
      |> maybe_add_agent()
    end

    defp instance_argv(igniter) do
      case Keyword.get(igniter.args.options, :jido_instance) do
        nil -> []
        value -> ["--jido-instance", value]
      end
    end

    defp maybe_add_agent(igniter) do
      case Keyword.get(igniter.args.options, :robot) do
        nil ->
          igniter

        robot ->
          argv = ["--robot", robot] ++ agent_argv(igniter)
          Igniter.compose_task(igniter, "bb_jido.add_agent", argv)
      end
    end

    defp agent_argv(igniter) do
      case Keyword.get(igniter.args.options, :agent) do
        nil -> []
        value -> ["--agent", value]
      end
    end
  end
else
  defmodule Mix.Tasks.BbJido.Install do
    @shortdoc "Installs bb_jido into a project"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_jido.install task requires igniter. Please install igniter and try again.

          mix igniter.install bb_jido
      """)

      exit({:shutdown, 1})
    end
  end
end
