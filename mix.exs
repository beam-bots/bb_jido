# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.MixProject do
  use Mix.Project

  @moduledoc """
  Autonomous agents for Beam Bots.
  """

  @version "0.1.1"

  def project do
    [
      aliases: aliases(),
      app: :bb_jido,
      consolidate_protocols: Mix.env() == :prod,
      deps: deps(),
      description: @moduledoc,
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  defp dialyzer, do: []

  defp package do
    [
      maintainers: ["James Harton <james@harton.nz>"],
      licenses: ["Apache-2.0"],
      links: %{
        "Source" => "https://github.com/beam-bots/bb_jido",
        "Sponsor" => "https://github.com/sponsors/jimsynz"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        ["README.md", "CHANGELOG.md"]
        |> Enum.concat(Path.wildcard("documentation/**/*.{md,livemd,cheatmd}")),
      groups_for_extras: [
        Tutorials: ~r/tutorials\//
      ],
      source_ref: "main",
      source_url: "https://github.com/beam-bots/bb_jido"
    ]
  end

  defp aliases, do: []

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bb, bb_dep("~> 0.12")},

      # dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.2", only: :test, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(env) when env in [:dev, :test], do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp bb_dep(default) do
    case System.get_env("BB_VERSION") do
      nil -> default
      "local" -> [path: "../bb", override: true]
      "main" -> [git: "https://github.com/beam-bots/bb.git", override: true]
      version -> "~> #{version}"
    end
  end
end
