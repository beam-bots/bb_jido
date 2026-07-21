# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Action.WaitForStateTest do
  use ExUnit.Case, async: false

  alias BB.Jido.Action.WaitForState
  alias BB.Jido.TestRobot
  alias BB.Message
  alias BB.StateMachine.Transition

  setup do
    start_supervised!({TestRobot, simulation: :kinematic})
    :ok
  end

  defp arm! do
    {:ok, cmd} = TestRobot.arm(%{})
    {:ok, :armed, _} = BB.Command.await(cmd)
  end

  defp subscriber_pids do
    TestRobot
    |> BB.PubSub.subscribers([:state_machine])
    |> Enum.map(&elem(&1, 0))
  end

  defp publish_transition(to) do
    message = Message.new!(Transition, :state_machine, from: :idle, to: to)
    BB.PubSub.publish(TestRobot, [:state_machine], message)
  end

  test "returns immediately when the robot is already in an operational target state" do
    arm!()

    assert {:ok, %{state: :idle}} =
             WaitForState.run(%{robot: TestRobot, target: :idle, timeout: 1_000}, %{})
  end

  test "returns immediately when the robot is already armed" do
    arm!()

    assert {:ok, %{state: :armed}} =
             WaitForState.run(%{robot: TestRobot, target: :armed, timeout: 1_000}, %{})
  end

  test "returns immediately when the robot is already disarmed" do
    assert {:ok, %{state: :disarmed}} =
             WaitForState.run(%{robot: TestRobot, target: :disarmed, timeout: 1_000}, %{})
  end

  test "waits for a future transition into the target state" do
    task =
      Task.async(fn ->
        WaitForState.run(%{robot: TestRobot, target: :armed, timeout: 5_000}, %{})
      end)

    Process.sleep(50)
    arm!()

    assert {:ok, %{state: :armed}} = Task.await(task)
  end

  test "the timeout is a total deadline even when unrelated transitions keep arriving" do
    pump =
      spawn(fn ->
        for _ <- 1..20 do
          publish_transition(:executing)
          Process.sleep(50)
        end
      end)

    started = System.monotonic_time(:millisecond)

    assert {:error, :timeout} =
             WaitForState.run(%{robot: TestRobot, target: :never_reached, timeout: 300}, %{})

    elapsed = System.monotonic_time(:millisecond) - started
    Process.exit(pump, :kill)

    assert elapsed >= 300
    assert elapsed < 900
  end

  test "preserves a caller's existing subscription on the fast path" do
    {:ok, _} = BB.PubSub.subscribe(TestRobot, [:state_machine])
    arm!()

    assert {:ok, %{state: :armed}} =
             WaitForState.run(%{robot: TestRobot, target: :armed, timeout: 1_000}, %{})

    assert self() in subscriber_pids()

    publish_transition(:executing)
    assert_receive {:bb, [:state_machine], %Message{payload: %Transition{to: :executing}}}, 500
  end

  test "preserves a caller's existing subscription after a timed-out wait" do
    {:ok, _} = BB.PubSub.subscribe(TestRobot, [:state_machine])

    assert {:error, :timeout} =
             WaitForState.run(%{robot: TestRobot, target: :never_reached, timeout: 100}, %{})

    assert self() in subscriber_pids()

    publish_transition(:executing)
    assert_receive {:bb, [:state_machine], %Message{payload: %Transition{to: :executing}}}, 500
  end

  test "leaves no pubsub messages in the caller's mailbox" do
    pump =
      spawn(fn ->
        for _ <- 1..10 do
          publish_transition(:executing)
          Process.sleep(20)
        end
      end)

    assert {:error, :timeout} =
             WaitForState.run(%{robot: TestRobot, target: :never_reached, timeout: 150}, %{})

    Process.exit(pump, :kill)
    refute_received {:bb, _path, _message}
  end
end
