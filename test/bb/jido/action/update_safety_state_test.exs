# SPDX-FileCopyrightText: 2026 Holden Oullette
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.UpdateSafetyStateTest do
  use ExUnit.Case, async: true

  alias BB.Jido.Action.UpdateSafetyState
  alias BB.Message
  alias BB.StateMachine.Transition
  alias Jido.Agent.StateOp

  defp transition_params(to) do
    %{
      robot: SomeRobot,
      path: [:state_machine],
      message: %Message{
        monotonic_time: 0,
        wall_time: 0,
        node: node(),
        frame_id: :state_machine,
        payload: %Transition{from: :disarmed, to: to}
      }
    }
  end

  for safety_state <- [:armed, :disarmed, :disarming, :error] do
    test "caches #{inspect(safety_state)} via a SetPath state op" do
      assert {:ok, %{}, [op]} =
               UpdateSafetyState.run(transition_params(unquote(safety_state)), %{})

      assert %StateOp.SetPath{path: [:robot, :safety_state], value: unquote(safety_state)} = op
    end
  end

  test "ignores operational state-machine transitions" do
    assert {:ok, %{}} = UpdateSafetyState.run(transition_params(:executing), %{})
  end

  test "ignores params without a transition payload" do
    assert {:ok, %{}} = UpdateSafetyState.run(%{message: :not_a_message}, %{})
    assert {:ok, %{}} = UpdateSafetyState.run(%{}, %{})
  end
end
