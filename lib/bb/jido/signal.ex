# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Jido.Signal do
  @moduledoc """
  Canonical mapping from `BB.PubSub` messages to `Jido.Signal` structs.

  PubSub subscribers receive `{:bb, source_path, %BB.Message{}}`. This module
  converts those into `Jido.Signal` structs with stable, queryable type strings
  following the `bb.*` namespace.

  ## Naming convention

  - `bb.state.transition` — robot state machine transitions (payload
    `BB.StateMachine.Transition`).
  - `bb.safety.error` — safety hardware errors (payload
    `BB.Safety.HardwareError`).
  - `bb.parameter.changed` — parameter updates (payload `BB.Parameter.Changed`).
  - `bb.pubsub.<path>` — generic envelope for any other PubSub message, where
    `<path>` is the dotted source path (e.g. `bb.pubsub.sensor.joint_state`).

  Source follows the `/bb/<robot_module>` convention for traceability, and
  the CloudEvents `subject` attribute carries the robot module name so
  handlers can identify the robot without unpacking `data`.
  """

  alias BB.Message

  @doc """
  Converts a `BB.PubSub` delivery into a `Jido.Signal`.

  - `robot` is the robot module that owns the subscription (used to build the
    signal source URI; falls back to the robot recorded on the message itself).
  - `source_path` is the publisher's full path as delivered by `BB.PubSub`.
  - `message` is the `%BB.Message{}` payload.
  """
  @spec from_pubsub(module() | nil, [atom()], Message.t()) :: Jido.Signal.t()
  def from_pubsub(robot, source_path, %Message{} = message)
      when is_list(source_path) do
    resolved_robot = robot || message.robot

    Jido.Signal.new!(
      type_for(source_path, message.payload),
      %{
        robot: resolved_robot,
        path: source_path,
        message: message
      },
      source: source(resolved_robot),
      subject: subject(resolved_robot)
    )
  end

  @doc """
  Returns the canonical signal type string for a given path/payload pair.

  Specialised types are recognised for well-known payload modules so that
  agents can subscribe to (for example) `bb.state.transition` regardless of
  the path the publisher used.
  """
  @spec type_for([atom()], struct() | nil) :: String.t()
  def type_for(_path, %BB.StateMachine.Transition{}), do: "bb.state.transition"
  def type_for(_path, %BB.Safety.HardwareError{}), do: "bb.safety.error"

  def type_for(path, _payload) do
    "bb.pubsub." <> Enum.map_join(path, ".", &Atom.to_string/1)
  end

  @doc """
  Returns the canonical signal source string for a robot module.
  """
  @spec source(module() | nil) :: String.t()
  def source(nil), do: "/bb"
  def source(robot) when is_atom(robot), do: "/bb/" <> inspect(robot)

  @doc """
  Returns the CloudEvents `subject` for a robot module — the robot's
  module name, or `nil` when the robot is unknown.
  """
  @spec subject(module() | nil) :: String.t() | nil
  def subject(nil), do: nil
  def subject(robot) when is_atom(robot), do: inspect(robot)
end
