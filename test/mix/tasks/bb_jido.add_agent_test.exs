# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.BbJido.AddAgentTest do
  use ExUnit.Case
  import Igniter.Test

  @moduletag :igniter

  test "creates an agent module named after the robot" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_agent", ["--robot", "Test.Robot"])
    |> assert_creates("lib/test/robot/agent.ex", """
    defmodule Test.Robot.Agent do
      use Jido.Agent,
        name: "agent",
        plugins: [
          {BB.Jido.Plugin.Robot, %{robot: Test.Robot}}
        ]
    end
    """)
  end

  test "honours --agent and --name" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_agent", [
      "--robot",
      "Test.Robot",
      "--agent",
      "Test.MainAgent",
      "--name",
      "main_robot"
    ])
    |> assert_creates("lib/test/main_agent.ex", """
    defmodule Test.MainAgent do
      use Jido.Agent,
        name: "main_robot",
        plugins: [
          {BB.Jido.Plugin.Robot, %{robot: Test.Robot}}
        ]
    end
    """)
  end

  test "is idempotent" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_agent", ["--robot", "Test.Robot"])
    |> apply_igniter!()
    |> Igniter.compose_task("bb_jido.add_agent", ["--robot", "Test.Robot"])
    |> assert_unchanged()
  end
end
