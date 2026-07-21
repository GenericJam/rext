defmodule Rext.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # The socket bridge listens only when it's the active transport. In NIF
    # mode the in-process host owns the render path, so no TCP listener runs.
    children =
      transport_children() ++
        [{DynamicSupervisor, name: Rext.WindowSupervisor, strategy: :one_for_one}]

    opts = [strategy: :one_for_one, name: Rext.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp transport_children do
    case Application.get_env(:rext, :transport, Rext.Bridge) do
      Rext.Bridge -> [{Rext.Bridge, port: Rext.Bridge.resolve_port()}]
      _ -> []
    end
  end
end
