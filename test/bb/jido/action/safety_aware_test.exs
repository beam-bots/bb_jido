# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.SafetyAwareTest do
  use ExUnit.Case, async: false

  alias BB.Jido.TestRobot

  defmodule GuardedAction do
    @moduledoc false
    use Jido.Action,
      name: "guarded_action",
      schema: [robot: [type: :atom, required: true]]

    use BB.Jido.Action.SafetyAware

    @impl Jido.Action
    def run(%{robot: robot}, _context) do
      {:ok, %{ran: true, robot: robot}}
    end
  end

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    :ok
  end

  test "blocks the wrapped run/2 when robot is not armed" do
    assert {:error, {:safety_not_armed, :disarmed}} =
             GuardedAction.run(%{robot: TestRobot}, %{})
  end

  test "passes through when robot is armed" do
    {:ok, cmd} = TestRobot.arm(%{})
    {:ok, :armed, _} = BB.Command.await(cmd)

    assert {:ok, %{ran: true, robot: TestRobot}} =
             GuardedAction.run(%{robot: TestRobot}, %{})
  end

  test "errors with :robot_not_specified when no robot is given" do
    assert {:error, :robot_not_specified} = GuardedAction.run(%{}, %{})
  end
end
