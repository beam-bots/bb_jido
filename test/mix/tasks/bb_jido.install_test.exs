# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.BbJido.InstallTest do
  use ExUnit.Case
  import Igniter.Test

  @moduletag :igniter

  test "without --robot only adds the Jido instance" do
    igniter =
      test_project()
      |> Igniter.compose_task("bb_jido.install")

    assert_creates(igniter, "lib/test/jido.ex")
    refute Rewrite.has_source?(igniter.rewrite, "lib/test/robot/agent.ex")
  end

  test "with --robot also adds an agent module" do
    igniter =
      test_project()
      |> Igniter.compose_task("bb_jido.install", ["--robot", "Test.Robot"])

    assert_creates(igniter, "lib/test/jido.ex")
    assert_creates(igniter, "lib/test/robot/agent.ex")
  end

  test "installation is idempotent" do
    test_project()
    |> Igniter.compose_task("bb_jido.install", ["--robot", "Test.Robot"])
    |> apply_igniter!()
    |> Igniter.compose_task("bb_jido.install", ["--robot", "Test.Robot"])
    |> assert_unchanged()
  end
end
