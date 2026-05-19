# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.CommandTest do
  use ExUnit.Case, async: false

  alias BB.Jido.Action.Command
  alias BB.Jido.TestRobot

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    {:ok, cmd} = TestRobot.arm(%{})
    {:ok, :armed, _} = BB.Command.await(cmd)
    :ok
  end

  test "runs a successful command and returns the outcome" do
    assert {:ok, result} =
             Command.run(
               %{robot: TestRobot, command: :test_succeed, goal: %{value: :hello}},
               %{}
             )

    assert result.robot == TestRobot
    assert result.command == :test_succeed
    assert result.goal == %{value: :hello}
    assert result.outcome == :hello
  end

  test "wraps command-level errors as {:command_failed, reason}" do
    assert {:error, {:command_failed, :boom}} =
             Command.run(
               %{robot: TestRobot, command: :test_fail, goal: %{reason: :boom}},
               %{}
             )
  end

  test "returns :safety_disarmed when the command is denied for non-armed robots" do
    {:ok, cmd} = TestRobot.disarm(%{})
    {:ok, :disarmed, _} = BB.Command.await(cmd)

    assert {:error, {:command_failed, _reason}} =
             Command.run(
               %{robot: TestRobot, command: :test_succeed, goal: %{}},
               %{}
             )
  end
end
