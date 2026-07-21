defmodule Rect.App do
  @moduledoc """
  Behaviour for a rect application's entry point.

  Where mob's `Mob.App` declares mobile navigation (`stack`/`tab_bar`/`drawer`),
  rect's app declares the set of windows the app opens — the desktop paradigm.
  Menus are declared here too (stubbed for the prototype; the menu bar is a
  desktop-native concern with no mobile analogue).

      defmodule MyApp do
        use Rect.App

        def windows do
          [
            {MyApp.CounterWindow, id: "main", title: "Counter", size: {420, 300}}
          ]
        end
      end

  Then `Rect.boot(MyApp)` opens them.
  """

  @callback windows() :: [{module(), keyword()}]
  @callback menu() :: [map()]

  @optional_callbacks [menu: 0]

  defmacro __using__(_opts) do
    quote do
      @behaviour Rect.App
      def menu, do: []
      defoverridable menu: 0
    end
  end
end
