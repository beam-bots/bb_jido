# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.BbJido.AddJidoInstanceTest do
  use ExUnit.Case
  import Igniter.Test

  @moduletag :igniter

  test "creates a Jido instance module with the default name" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_jido_instance")
    |> assert_creates("lib/test/jido.ex", """
    defmodule Test.Jido do
      use Jido, otp_app: :test
    end
    """)
  end

  test "honours --jido-instance" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_jido_instance", ["--jido-instance", "Test.AgentRuntime"])
    |> assert_creates("lib/test/agent_runtime.ex")
  end

  test "adds {Jido, name: ...} to the supervision tree" do
    igniter =
      test_project()
      |> Igniter.compose_task("bb_jido.add_jido_instance")

    assert_creates(igniter, "lib/test/application.ex")

    {_, source} = Rewrite.source(igniter.rewrite, "lib/test/application.ex")
    assert source.content =~ "{Jido, [name: Test.Jido]}"
  end

  test "is idempotent" do
    test_project()
    |> Igniter.compose_task("bb_jido.add_jido_instance")
    |> apply_igniter!()
    |> Igniter.compose_task("bb_jido.add_jido_instance")
    |> assert_unchanged()
  end
end
