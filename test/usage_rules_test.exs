# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.UsageRulesTest do
  use ExUnit.Case, async: true

  test "usage-rules.md exists and carries an SPDX header" do
    assert File.regular?("usage-rules.md")
    assert File.read!("usage-rules.md") =~ "SPDX-License-Identifier"
  end

  test "usage-rules.md is included in the hex package files" do
    files = Keyword.fetch!(Mix.Project.config()[:package], :files)
    assert "usage-rules.md" in files
  end
end
