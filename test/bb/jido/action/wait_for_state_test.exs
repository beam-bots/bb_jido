# SPDX-FileCopyrightText: 2026 Holden Oullette
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

  defp drain_late_results(acc \\ []) do
    receive do
      {ref, result} when is_reference(ref) -> drain_late_results([{ref, result} | acc])
    after
      0 -> acc
    end
  end

  defp subscriber_pids do
    TestRobot
    |> BB.PubSub.subscribers([:state_machine])
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp await(condition, failure_message, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_condition(condition, failure_message, deadline)
  end

  defp poll_condition(condition, failure_message, deadline) do
    cond do
      condition.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk(failure_message)

      true ->
        Process.sleep(10)
        poll_condition(condition, failure_message, deadline)
    end
  end

  defp publish_transition(to) do
    message = Message.new!(Transition, :state_machine, from: :idle, to: to)
    BB.PubSub.publish(TestRobot, [:state_machine], message)
  end

  test "output schema requires the documented result fields" do
    assert {:ok, _} = WaitForState.validate_output(%{state: :idle})
    assert {:error, _} = WaitForState.validate_output(%{})
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

  test "fast-path waits never leak late waiter results into the caller mailbox" do
    arm!()

    pump =
      spawn(fn ->
        loop = fn loop ->
          publish_transition(:armed)
          loop.(loop)
        end

        loop.(loop)
      end)

    for _ <- 1..500 do
      assert {:ok, %{state: :armed}} =
               WaitForState.run(%{robot: TestRobot, target: :armed, timeout: 1_000}, %{})
    end

    Process.exit(pump, :kill)

    assert drain_late_results() == []
  end

  test "a killed caller takes the waiter's subscription down with it" do
    baseline = subscriber_pids()

    caller =
      spawn(fn ->
        WaitForState.run(%{robot: TestRobot, target: :never_reached, timeout: 60_000}, %{})
      end)

    await(fn -> subscriber_pids() != baseline end, "waiter never subscribed")

    Process.exit(caller, :kill)

    await(
      fn -> subscriber_pids() == baseline end,
      "waiter subscription survived its caller"
    )
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
