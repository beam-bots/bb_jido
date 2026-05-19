# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.TestRobot do
  @moduledoc """
  A minimal robot for testing bb_jido.
  """

  use BB
  import BB.Unit

  settings do
    name(:bb_jido_test_robot)
  end

  topology do
    link :base do
      joint :joint1 do
        type(:revolute)

        origin do
          z(~u(0.1 meter))
        end

        limit do
          lower(~u(-180 degree))
          upper(~u(180 degree))
          effort(~u(10 newton_meter))
          velocity(~u(180 degree_per_second))
        end

        link(:link1)
      end
    end
  end

  commands do
    command :arm do
      handler(BB.Command.Arm)
      allowed_states([:disarmed])
    end

    command :disarm do
      handler(BB.Command.Disarm)
      allowed_states(:*)
      cancel(:*)
    end

    command :test_succeed do
      handler(BB.Jido.TestCommands.Succeed)
      allowed_states([:idle])
    end

    command :test_fail do
      handler(BB.Jido.TestCommands.Fail)
      allowed_states([:idle])
    end
  end
end

defmodule BB.Jido.TestCommands.Succeed do
  @moduledoc false
  use BB.Command

  @impl BB.Command
  def handle_command(goal, _context, state) do
    result = {:ok, Map.get(goal, :value, :success)}
    {:stop, :normal, Map.put(state, :result, result)}
  end

  @impl BB.Command
  def result(%{result: result}) when result != nil, do: result
  def result(_state), do: {:error, :no_result}
end

defmodule BB.Jido.TestCommands.Fail do
  @moduledoc false
  use BB.Command

  @impl BB.Command
  def handle_command(goal, _context, state) do
    reason = Map.get(goal, :reason, :test_failure)
    {:stop, :normal, Map.put(state, :result, {:error, reason})}
  end

  @impl BB.Command
  def result(%{result: result}) when result != nil, do: result
  def result(_state), do: {:error, :no_result}
end
