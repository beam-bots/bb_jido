# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.RecordSafetyErrorTest do
  use ExUnit.Case, async: true

  alias BB.Jido.Action.RecordSafetyError
  alias BB.Message
  alias BB.Safety.HardwareError
  alias Jido.Agent.StateOp

  test "records the hardware error via a SetPath state op" do
    error = %HardwareError{path: [:gpio, :estop], error: :stuck_pin}

    params = %{
      robot: SomeRobot,
      path: [:safety, :error],
      message: %Message{
        monotonic_time: 0,
        wall_time: 0,
        node: node(),
        frame_id: :safety,
        payload: error
      }
    }

    assert {:ok, %{}, [op]} = RecordSafetyError.run(params, %{})
    assert %StateOp.SetPath{path: [:robot, :last_safety_error], value: ^error} = op
  end

  test "ignores params without a hardware-error payload" do
    assert {:ok, %{}} = RecordSafetyError.run(%{message: :not_a_message}, %{})
    assert {:ok, %{}} = RecordSafetyError.run(%{}, %{})
  end
end
