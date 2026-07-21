defmodule Rect do
  @moduledoc """
  Rect — a BEAM-on-desktop UI framework for Elixir.

  Rect is mob's desktop sibling. It keeps mob's programming model verbatim — a
  unit of UI is a supervised GenServer that produces a component tree, the tree
  is serialized and handed to a native render backend, and events come back over
  the same channel — but it commits to *desktop* paradigm and concerns:

    * the unit is `Rect.Window`, and apps run many windows at once;
    * the render backend is SwiftUI on macOS and Compose Multiplatform on
      Windows/Linux (mirroring mob's SwiftUI + Compose split, re-pointed at
      desktop targets);
    * dev/agent tooling lives in `rect_dev`, project generation in `rect_new`.

  Rect was seeded by copying mob's platform-agnostic core rather than sharing a
  library up front; a common `beam_native_ui` package is a later refactor if the
  duplication proves significant and enduring.

  ## Opening a window

      {:ok, _pid} = Rect.open(MyApp.CounterWindow, id: "main", title: "Counter")
  """

  @doc """
  Open a window under the window supervisor.

  Options are passed to `Rect.Window.start_link/3` (`:id`, `:title`, `:size`).
  """
  @spec open(module(), keyword()) :: DynamicSupervisor.on_start_child()
  def open(window_module, opts \\ []) do
    DynamicSupervisor.start_child(
      Rect.WindowSupervisor,
      %{
        id: {Rect.Window, opts[:id] || "main"},
        start: {Rect.Window, :start_link, [window_module, %{}, opts]},
        restart: :transient
      }
    )
  end

  @doc "Boot every window declared by an app module (see `Rect.App`)."
  @spec boot(module()) :: :ok
  def boot(app_module) do
    for {mod, opts} <- app_module.windows(), do: open(mod, opts)
    :ok
  end
end
