defmodule Rect.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # The socket bridge listens only when it's the active transport. In NIF
    # mode the in-process host owns the render path, so no TCP listener runs.
    children =
      transport_children() ++
        [{DynamicSupervisor, name: Rect.WindowSupervisor, strategy: :one_for_one}]

    opts = [strategy: :one_for_one, name: Rect.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp transport_children do
    case Application.get_env(:rect, :transport, Rect.Bridge) do
      Rect.Bridge -> [{Rect.Bridge, port: Rect.Bridge.resolve_port()}]
      _ -> []
    end
  end
end
