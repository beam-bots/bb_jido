# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Telemetry do
  @moduledoc """
  Telemetry events emitted by `bb_jido`.

  Two event spans are emitted, both following the standard
  `:telemetry.span/3` conventions:

  - `[:bb_jido, :action, :command]` — wraps execution of
    `BB.Jido.Action.Command`.
  - `[:bb_jido, :action, :reactor]` — wraps execution of
    `BB.Jido.Action.Reactor`.

  Each `:start`, `:stop`, and `:exception` event carries measurements with
  `:system_time`/`:duration` and metadata including `:robot` plus the
  action-specific identifier (`:command` or `:reactor`).

  A `[:bb_jido, :signal]` event is emitted for every signal forwarded by
  `BB.Jido.PubSubBridge`, with metadata `%{robot: ..., type: ...}`.
  """

  @doc """
  Span helper for telemetry-wrapped action execution. Returns whatever
  `fun` returns.
  """
  @spec span([atom()], map(), (-> result)) :: result when result: var
  def span(event_prefix, metadata, fun) when is_function(fun, 0) do
    :telemetry.span(event_prefix, metadata, fn ->
      result = fun.()
      {result, Map.put(metadata, :result_tag, result_tag(result))}
    end)
  end

  @doc """
  Emits a `[:bb_jido, :signal]` event for a forwarded signal.
  """
  @spec emit_signal(module() | nil, String.t()) :: :ok
  def emit_signal(robot, type) when is_binary(type) do
    :telemetry.execute(
      [:bb_jido, :signal],
      %{count: 1},
      %{robot: robot, type: type}
    )
  end

  defp result_tag({:ok, _}), do: :ok
  defp result_tag({:ok, _, _}), do: :ok
  defp result_tag({:error, _}), do: :error
  defp result_tag(_), do: :other
end
