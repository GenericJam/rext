defmodule Rext.Bridge do
  @moduledoc """
  Owns the wire between the BEAM and the render backend.

  For the prototype the backend is an out-of-process macOS SwiftUI renderer that
  connects back over a localhost TCP socket, framed with a 4-byte length header
  (`{:packet, 4}` on both ends). The bridge:

    * listens and accepts the renderer connection (tolerating reconnects),
    * receives interaction events and routes them to the owning `Rext.Window`,
    * sends render frames, buffering the latest frame per window so a renderer
      that connects *after* a window first rendered still gets current state.

  This is the one seam that changes when we move to an in-process NIF host: the
  render frame goes to a NIF call instead of a socket, and events arrive via
  `enif_send` instead of `{:tcp, ...}`. Everything above this module (Window,
  Renderer, Socket, Test) is unchanged by that swap — which is the whole point
  of keeping the transport isolated here.

  Re-entrancy note (see mob's CLAUDE.md, "transport-handler reentrancy"): event
  routing does a synchronous `Rext.Window.dispatch/3`, and the window's render
  path casts back here asynchronously. The cast (never a call) is what keeps the
  bridge from calling into a window that is mid-call into the bridge.
  """

  use GenServer
  @behaviour Rext.Transport
  require Logger

  @default_port 8137

  @impl Rext.Transport
  def available?, do: Process.whereis(__MODULE__) != nil

  @doc "The compiled-in default bridge port."
  @spec default_port() :: pos_integer()
  def default_port, do: @default_port

  @doc """
  Resolve the bridge port, highest precedence first:

    1. `REXT_PORT` env var — the CLI path (`mix rext.run --port N` sets it).
    2. `config :rext, :port, N` — project config.
    3. the compiled-in default (#{@default_port}).

  A conflict on the resolved port still falls back to an ephemeral one at
  listen time (see `init/1`), so this is a preference, not a hard requirement.
  """
  @spec resolve_port() :: non_neg_integer()
  def resolve_port do
    env = System.get_env("REXT_PORT")

    cond do
      is_binary(env) and env != "" -> String.to_integer(env)
      true -> Application.get_env(:rext, :port) || @default_port
    end
  end

  # ── Public API ──────────────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc "Register a window process so events for `window_id` route to it."
  @impl Rext.Transport
  @spec register(String.t(), pid()) :: :ok
  def register(window_id, pid), do: GenServer.call(__MODULE__, {:register, window_id, pid})

  @doc "Push a window's current tree to the render backend (async, ordered)."
  @impl Rext.Transport
  @spec render(String.t(), map()) :: :ok
  def render(window_id, tree), do: GenServer.cast(__MODULE__, {:render, window_id, tree})

  @doc "The actual TCP port the bridge is listening on."
  @spec port() :: non_neg_integer()
  def port, do: GenServer.call(__MODULE__, :port)

  @doc "Whether a render backend is currently connected."
  @spec connected?() :: boolean()
  def connected?, do: GenServer.call(__MODULE__, :connected?)

  # ── GenServer ─────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    requested = opts[:port] || @default_port

    case open_listen(requested) do
      {:ok, lsock, actual_port} ->
        if actual_port != requested and requested != 0 do
          Logger.warning(
            "[rext] port #{requested} in use (another rext instance?) — " <>
              "bridge listening on #{actual_port} instead"
          )
        end

        parent = self()
        spawn_link(fn -> accept_loop(lsock, parent) end)
        Logger.info("[rext] bridge listening on 127.0.0.1:#{actual_port}")

        {:ok,
         %{
           lsock: lsock,
           port: actual_port,
           sock: nil,
           # window_id => pid
           windows: %{},
           # window_id => latest frame binary
           frames: %{}
         }}

      {:error, reason} ->
        # A hard listen failure (not a mere port conflict, which we fall back
        # from below). Stop cleanly rather than crashing the whole app with a
        # MatchError — the supervisor reports a clear reason.
        {:stop, {:bridge_listen_failed, reason}}
    end
  end

  # Bind the requested port; on a conflict (another rext instance already holds
  # it), fall back to an OS-assigned ephemeral port rather than crashing. The
  # dev launcher reads the actual port back via `port/0`, so the fallback is
  # transparent to `mix rext.run` and the renderer it spawns.
  defp open_listen(port) do
    opts = [:binary, packet: 4, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]

    case :gen_tcp.listen(port, opts) do
      {:ok, lsock} ->
        {:ok, actual} = :inet.port(lsock)
        {:ok, lsock, actual}

      {:error, :eaddrinuse} when port != 0 ->
        open_listen(0)

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def handle_call({:register, window_id, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, put_in(state.windows[window_id], pid)}
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}
  def handle_call(:connected?, _from, state), do: {:reply, state.sock != nil, state}

  @impl true
  def handle_cast({:render, window_id, tree}, state) do
    frame = Rext.Renderer.frame(window_id, tree)
    if state.sock, do: :gen_tcp.send(state.sock, frame)
    {:noreply, put_in(state.frames[window_id], frame)}
  end

  @impl true
  def handle_info({:renderer_connected, sock}, state) do
    :inet.setopts(sock, active: true)
    Logger.info("[rext] render backend connected")
    # Flush the latest frame for every known window so a late-connecting
    # renderer immediately shows current state.
    for {_id, frame} <- state.frames, do: :gen_tcp.send(sock, frame)
    {:noreply, %{state | sock: sock}}
  end

  def handle_info({:tcp, _sock, data}, state) do
    route_event(:json.decode(data), state)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _sock}, state) do
    Logger.info("[rext] render backend disconnected")
    {:noreply, %{state | sock: nil}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    windows = for {id, p} <- state.windows, p != pid, into: %{}, do: {id, p}
    {:noreply, %{state | windows: windows}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internals ─────────────────────────────────────────────────────────────

  defp route_event(%{"t" => "event", "window" => window_id} = ev, state) do
    case state.windows[window_id] do
      nil ->
        Logger.warning("[rext] event for unknown window #{inspect(window_id)}")

      pid ->
        params = Map.take(ev, ["tag", "value"])
        Rext.Window.dispatch(pid, ev["event"] || "click", params)
    end
  end

  defp route_event(%{"t" => "hello"} = hello, _state) do
    Logger.info("[rext] renderer hello: #{inspect(hello["renderer"])}")
  end

  defp route_event(_other, _state), do: :ok

  defp accept_loop(lsock, bridge) do
    case :gen_tcp.accept(lsock) do
      {:ok, sock} ->
        :ok = :gen_tcp.controlling_process(sock, bridge)
        send(bridge, {:renderer_connected, sock})
        accept_loop(lsock, bridge)

      {:error, :closed} ->
        :ok
    end
  end
end
