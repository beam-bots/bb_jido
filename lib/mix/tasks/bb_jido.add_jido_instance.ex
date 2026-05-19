# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.BbJido.AddJidoInstance do
    @shortdoc "Adds a Jido supervisor instance module and wires it into the application"
    @moduledoc """
    #{@shortdoc}

    Creates a small module that declares your application's Jido instance and
    adds `{Jido, name: <module>}` to your application's supervision tree.

    ## Example

    ```bash
    mix bb_jido.add_jido_instance
    mix bb_jido.add_jido_instance --jido-instance MyApp.AgentRuntime
    ```

    ## Options

    * `--jido-instance` - The module name for the Jido instance (defaults to
      `{AppPrefix}.Jido`).
    """

    use Igniter.Mix.Task

    alias BB.Jido.Igniter, as: BBJidoIgniter
    alias Igniter.Project.Application
    alias Igniter.Project.Module

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [jido_instance: :string],
        aliases: [j: :jido_instance]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      jido_module = BBJidoIgniter.jido_instance_module(igniter)
      otp_app = Application.app_name(igniter)

      igniter
      |> create_jido_module(jido_module, otp_app)
      |> add_to_supervision_tree(jido_module)
    end

    defp create_jido_module(igniter, module, otp_app) do
      case Module.module_exists(igniter, module) do
        {true, igniter} ->
          igniter

        {false, igniter} ->
          Module.create_module(igniter, module, """
          use Jido, otp_app: #{inspect(otp_app)}
          """)
      end
    end

    defp add_to_supervision_tree(igniter, jido_module) do
      Application.add_new_child(
        igniter,
        {Jido, [name: jido_module]},
        after: fn _ -> true end
      )
    end
  end
else
  defmodule Mix.Tasks.BbJido.AddJidoInstance do
    @shortdoc "Adds a Jido supervisor instance module and wires it into the application"
    @moduledoc false
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The bb_jido.add_jido_instance task requires igniter.

          mix deps.get
          mix bb_jido.add_jido_instance
      """)

      exit({:shutdown, 1})
    end
  end
end
