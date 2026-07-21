defmodule Rext.Transport do
  @moduledoc """
  The seam between a window and its render backend.

  Two implementations ship: `Rext.Bridge` (out-of-process, socket — the Port
  partner used for the socket prototype and for remote/browser renderers) and
  `Rext.NifBridge` (in-process, NIF — the mob-faithful path where the native
  host owns `main()` and embeds the BEAM). Everything above this behaviour
  (Window, Renderer, Socket, Test) is identical across both; selecting a
  transport is one config line:

      config :rext, :transport, Rext.NifBridge
  """

  @callback available?() :: boolean()
  @callback render(window_id :: String.t(), tree :: map()) :: any()
  @callback register(window_id :: String.t(), pid :: pid()) :: any()

  @doc "The configured transport module (defaults to the socket bridge)."
  @spec impl() :: module()
  def impl, do: Application.get_env(:rext, :transport, Rext.Bridge)
end
