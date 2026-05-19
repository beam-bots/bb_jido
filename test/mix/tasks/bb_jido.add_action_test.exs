# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.BbJido.AddActionTest do
  use ExUnit.Case
  import Igniter.Test

  @moduletag :igniter

  test "creates a plain action module" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_action", ["Test.Actions.MyAction"])
    |> assert_creates("lib/test/actions/my_action.ex", """
    defmodule Test.Actions.MyAction do
      use Jido.Action,
        name: "my_action",
        schema: []

      @impl Jido.Action
      def run(_params, _context) do
        {:ok, %{}}
      end
    end
    """)
  end

  test "honours --description and --name" do
    igniter =
      test_project()
      |> Igniter.compose_task("bb_jido.add_action", [
        "Test.Actions.Teleop",
        "--name",
        "teleop_step",
        "--description",
        "Drive the robot from a teleop joystick"
      ])

    {_, source} = Rewrite.source(igniter.rewrite, "lib/test/actions/teleop.ex")
    assert source.content =~ ~s(name: "teleop_step")
    assert source.content =~ ~s(description: "Drive the robot from a teleop joystick")
  end

  test "with --safety-aware adds the mixin and a :robot field" do
    igniter =
      test_project()
      |> Igniter.compose_task("bb_jido.add_action", [
        "Test.Actions.MovePose",
        "--safety-aware"
      ])

    {_, source} = Rewrite.source(igniter.rewrite, "lib/test/actions/move_pose.ex")
    assert source.content =~ "use BB.Jido.Action.SafetyAware"
    assert source.content =~ "robot: [type: :atom, required: true"
    assert source.content =~ "def run(%{robot: _robot} = _params"
  end

  test "is idempotent" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_action", ["Test.Actions.MyAction"])
    |> apply_igniter!()
    |> Igniter.compose_task("bb_jido.add_action", ["Test.Actions.MyAction"])
    |> assert_unchanged()
  end
end
