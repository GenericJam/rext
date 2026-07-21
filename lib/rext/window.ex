defmodule Rext.Window do
  @moduledoc """
  Behaviour + GenServer wrapper for a desktop window.

  A window is one supervised GenServer whose state is a `Rext.Socket`. This is
  the same "one process per unit of UI" model as `Mob.Screen` — you get crash
  isolation (a buggy `handle_event` restarts its own window, not the app), and
  the BEAM's concurrency tools (monitors, hot code push, RPC) work on windows
  with no framework-specific scaffolding.

  What's desktop-native here, versus mob's mobile paradigm: the unit is a
  *window*, and an app is expected to run several at once — a document window, an
  inspector, a preferences panel — each its own `Rext.Window` process. There is
  no navigation stack; "go to another view" on desktop is "open/focus another
  window", which is just starting another process.

      defmodule MyApp.CounterWindow do
        use Rext.Window

        def mount(_params, socket) do
          {:ok, Rext.Socket.assign(socket, :count, 0)}
        end

        def render(assigns) do
          %{type: :column, props: %{gap: :space_md, padding: :space_lg},
            children: [
              %{type: :text,   props: %{text: "Count: \#{assigns.count}"}, children: []},
              %{type: :button, props: %{label: "Increment", on_click: :inc}, children: []}
            ]}
        end

        def handle_event("click", %{"tag" => "inc"}, socket) do
          {:noreply, Rext.Socket.update(socket, :count, &(&1 + 1))}
        end
      end
  """

  @type socket :: Rext.Socket.t()

  @callback mount(params :: map(), socket :: socket()) :: {:ok, socket()} | {:error, term()}
  @callback render(assigns :: map()) :: map()
  @callback handle_event(event :: String.t(), params :: map(), socket :: socket()) ::
              {:noreply, socket()}
  @callback handle_info(msg :: term(), socket :: socket()) :: {:noreply, socket()}
  @callback terminate(reason :: term(), socket :: socket()) :: term()

  @optional_callbacks [handle_event: 3, handle_info: 2, terminate: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Rext.Window

      def handle_info(_msg, socket), do: {:noreply, socket}
      def terminate(_reason, _socket), do: :ok

      def handle_event(event, _params, _socket) do
        raise "unhandled event #{inspect(event)} in #{inspect(__MODULE__)}. " <>
                "Add a handle_event/3 clause to handle it."
      end

      defoverridable handle_info: 2, terminate: 2, handle_event: 3
    end
  end

  # ── GenServer wrapper ─────────────────────────────────────────────────────

  use GenServer

  @doc """
  Start a window process. Options: `:id`, `:title`, `:size`, and `:name` for
  process registration (defaults to a name derived from the window id so
  `Rext.Test` and the bridge can find it).
  """
  @spec start_link(module(), map(), keyword()) :: GenServer.on_start()
  def start_link(window_module, params \\ %{}, opts \\ []) do
    id = Keyword.get(opts, :id, "main")
    name = Keyword.get(opts, :name, via(id))
    GenServer.start_link(__MODULE__, {window_module, params, opts}, name: name)
  end

  @doc "Process name for a window id — how the bridge and Rext.Test address it."
  @spec via(String.t()) :: atom()
  def via(id), do: String.to_atom("rext_window_" <> id)

  @doc "Dispatch a UI event to the window. Synchronous — returns once processed."
  @spec dispatch(GenServer.server(), String.t(), map()) :: :ok
  def dispatch(server, event, params), do: GenServer.call(server, {:event, event, params})

  @doc "Return the window's current socket (testing/debugging)."
  @spec get_socket(GenServer.server()) :: socket()
  def get_socket(server), do: GenServer.call(server, :get_socket)

  @doc "Return `%{window:, assigns:, tree:}` for the live window (testing/debugging)."
  @spec inspect(GenServer.server()) :: map()
  def inspect(server), do: GenServer.call(server, :inspect)

  # ── Callbacks ─────────────────────────────────────────────────────────────

  @impl true
  def init({module, params, opts}) do
    socket =
      Rext.Socket.new(module,
        id: Keyword.get(opts, :id, "main"),
        title: Keyword.get(opts, :title, "Rext"),
        size: Keyword.get(opts, :size, {480, 360})
      )

    case module.mount(params, socket) do
      {:ok, mounted} ->
        register_with_bridge(mounted)
        {:ok, {module, render_and_push(module, mounted)}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:event, event, params}, _from, {module, socket}) do
    {:noreply, new_socket} = module.handle_event(event, params, socket)
    {:reply, :ok, {module, render_and_push(module, new_socket)}}
  end

  def handle_call(:get_socket, _from, {_m, socket} = state), do: {:reply, socket, state}

  def handle_call(:inspect, _from, {module, socket} = state) do
    info = %{
      window: module,
      id: Rext.Socket.id(socket),
      assigns: socket.assigns,
      tree: module.render(socket.assigns)
    }

    {:reply, info, state}
  end

  # UI event delivered by the NIF transport (enif_send). Routed to handle_event
  # exactly like a socket-delivered event, so window code is transport-agnostic.
  @impl true
  def handle_info({:rext_ui_event, event, params}, {module, socket}) do
    {:noreply, new_socket} = module.handle_event(event, params, socket)
    {:noreply, {module, render_and_push(module, new_socket)}}
  end

  def handle_info(msg, {module, socket}) do
    {:noreply, new_socket} = module.handle_info(msg, socket)
    {:noreply, {module, render_and_push(module, new_socket)}}
  end

  @impl true
  def terminate(reason, {module, socket}), do: module.terminate(reason, socket)

  # ── Render pipeline ─────────────────────────────────────────────────────────

  defp render_and_push(module, socket) do
    tree = module.render(socket.assigns)
    socket = Rext.Socket.put_rext(socket, :tree, tree)
    t = Rext.Transport.impl()
    if t.available?(), do: t.render(Rext.Socket.id(socket), tree)
    socket
  end

  defp register_with_bridge(socket) do
    t = Rext.Transport.impl()
    if t.available?(), do: t.register(Rext.Socket.id(socket), self())
  end
end
