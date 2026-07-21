defmodule Rext.NifBridge do
  @moduledoc """
  In-process render transport: the render frame goes to the `rext_nif` NIF (a
  direct call, no wire), and UI events arrive back as `{:rext_ui_event, event,
  params}` messages via `enif_send` — which `Rext.Window` handles identically to
  a socket event. This is the mob-faithful path: the native host owns `main()`
  and boots the embedded BEAM, exactly as mob's iOS app does.

  Selected via `config :rext, :transport, Rext.NifBridge` (the embedded host
  sets this at boot). When active, the NIF is present by construction — the host
  built and loaded it — so `available?/0` is simply true.
  """
  @behaviour Rext.Transport

  @impl true
  def available?, do: true

  @impl true
  def render(window_id, tree) do
    json = Rext.Renderer.frame(window_id, tree)
    :rext_nif.render(window_id, json)
  end

  @impl true
  def register(window_id, _pid) do
    # Called from the window process, so the NIF captures its pid (enif_self)
    # for routing UI events back.
    :rext_nif.register_window(window_id)
  end
end
