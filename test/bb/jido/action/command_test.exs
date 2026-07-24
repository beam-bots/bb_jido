# SPDX-FileCopyrightText: 2026 James Harton
# SPDX-FileCopyrightText: 2026 Holden Oullette
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

    refute Map.has_key?(result, :robot)
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

  test "returns :safety_disarmed when the command is denied for disarmed robots" do
    {:ok, cmd} = TestRobot.disarm(%{})
    {:ok, :disarmed, _} = BB.Command.await(cmd)

    assert {:error, :safety_disarmed} =
             Command.run(
               %{robot: TestRobot, command: :test_succeed, goal: %{}},
               %{}
             )
  end

  test "await timeouts are wrapped exactly once" do
    assert {:error, {:command_failed, :timeout}} =
             Command.run(
               %{robot: TestRobot, command: :test_hang, goal: %{}, timeout: 100},
               %{}
             )
  end

  test "output schema requires the documented result fields" do
    assert {:ok, _} =
             Command.validate_output(%{command: :test_succeed, goal: %{}, outcome: :hello})

    assert {:error, _} = Command.validate_output(%{})
  end

  test "non-disarm state rejections stay {:command_failed, reason}" do
    assert {:error, {:command_failed, %BB.Error.State.NotAllowed{current_state: :idle}}} =
             Command.run(
               %{robot: TestRobot, command: :arm, goal: %{}},
               %{}
             )
  end
end
