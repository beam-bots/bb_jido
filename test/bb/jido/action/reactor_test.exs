# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.ReactorTest do
  use ExUnit.Case, async: false

  alias BB.Jido.Action.Reactor, as: ReactorAction
  alias BB.Jido.TestRobot

  defmodule SuccessReactor do
    @moduledoc false
    use Reactor

    middlewares do
      middleware(BB.Reactor.Middleware.Context)
    end

    input(:value)

    step :do_command do
      impl({BB.Reactor.Step.Command, command: :test_succeed})
      argument(:value, input(:value))
    end

    return(:do_command)
  end

  defmodule FailReactor do
    @moduledoc false
    use Reactor

    middlewares do
      middleware(BB.Reactor.Middleware.Context)
    end

    input(:reason)

    step :do_command do
      impl({BB.Reactor.Step.Command, command: :test_fail})
      argument(:reason, input(:reason))
    end

    return(:do_command)
  end

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    {:ok, cmd} = TestRobot.arm(%{})
    {:ok, :armed, _} = BB.Command.await(cmd)
    :ok
  end

  test "runs a reactor and surfaces the result" do
    assert {:ok, %{reactor: SuccessReactor, result: result}} =
             ReactorAction.run(
               %{robot: TestRobot, reactor: SuccessReactor, inputs: %{value: :ok_value}},
               %{}
             )

    assert result.outcome == :ok_value
  end

  test "output schema requires the documented result fields" do
    assert {:ok, _} = ReactorAction.validate_output(%{reactor: SuccessReactor, result: :ok})
    assert {:error, _} = ReactorAction.validate_output(%{})
  end

  test "wraps reactor errors" do
    assert {:error, {:reactor_failed, _errors}} =
             ReactorAction.run(
               %{robot: TestRobot, reactor: FailReactor, inputs: %{reason: :nope}},
               %{}
             )
  end
end
