defmodule Rext.Bridge do
  @moduledoc """
  Owns the wire between the BEAM and the render backend.

  For the prototype the backend is an out-of-process macOS SwiftUI renderer that
  connects back over a localhost TCP socket, framed with a 4-byte length header
  (`{:packet, 4}` on both ends). The bridge:

    * listens and accepts renderer connections (many at once, tolerating
      reconnects),
    * receives interaction events and routes them to the owning `Rext.Window`,
    * sends render frames, buffering the latest frame per window so a renderer
      that connects *after* a window first rendered still gets current state.

  ## Many windows, many renderers

  One renderer surface draws one window — that is the desktop model, and it is
  why an app that opens three windows runs three renderer processes against this
  one bridge. Each renderer announces the window it draws in its `hello`, and
  frames are addressed to it; a renderer that announces nothing is sent every
  window's frames and filters client-side, which is what all three backends did
  before they announced.

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

  @doc "Whether at least one render backend is currently connected."
  @spec connected?() :: boolean()
  def connected?, do: GenServer.call(__MODULE__, :connected?)

  @doc """
  Ask the renderer drawing `window_id` to describe what it actually built.

  This is the one call that does **not** trust the BEAM's own view: `Rext.Test`
  can already read the tree a window *rendered*, but only the backend knows what
  it turned that into. A node the backend silently dropped — an unknown type, a
  frame that never arrived — shows up here and nowhere else.

  Returns `{:error, :no_renderer}` when nothing is drawing that window, and
  `{:error, :timeout}` if the renderer doesn't answer.
  """
  @spec describe(String.t(), timeout()) :: {:ok, map()} | {:error, :no_renderer | :timeout}
  def describe(window_id, timeout \\ 2_000) do
    GenServer.call(__MODULE__, {:describe, window_id}, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @doc """
  Window ids of the currently connected renderers.

  A renderer that hasn't announced a window (or announced before this was a
  protocol field) appears as `:all`. Mostly useful to `mix rext.run` and tests,
  which need to know when every window has a surface.
  """
  @spec renderers() :: [String.t() | :all]
  def renderers, do: GenServer.call(__MODULE__, :renderers)

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
           # socket => window id it draws, or :all until it announces one
           socks: %{},
           # window_id => pid
           windows: %{},
           # window_id => latest frame binary
           frames: %{},
           # describe ref => caller awaiting the reply
           pending: %{}
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
  def handle_call(:connected?, _from, state), do: {:reply, state.socks != %{}, state}
  def handle_call(:renderers, _from, state), do: {:reply, Map.values(state.socks), state}

  def handle_call({:describe, window_id}, from, state) do
    case Enum.find(state.socks, fn {_s, target} -> target == window_id end) do
      nil ->
        {:reply, {:error, :no_renderer}, state}

      {sock, _} ->
        ref = Integer.to_string(System.unique_integer([:positive]))
        frame = :json.encode(%{"t" => "describe", "window" => window_id, "ref" => ref})
        :gen_tcp.send(sock, IO.iodata_to_binary(frame))
        {:noreply, put_in(state.pending[ref], from)}
    end
  end

  @impl true
  def handle_cast({:render, window_id, tree}, state) do
    frame = Rext.Renderer.frame(window_id, tree)
    state = broadcast(state, frame, window_id)
    {:noreply, put_in(state.frames[window_id], frame)}
  end

  @impl true
  def handle_info({:renderer_connected, sock}, state) do
    :inet.setopts(sock, active: true)
    state = put_in(state.socks[sock], :all)
    Logger.info("[rext] render backend connected (#{map_size(state.socks)} attached)")
    # Flush every known window's latest frame: the renderer hasn't announced
    # which one it draws yet, and it filters client-side anyway.
    for {_id, frame} <- state.frames, do: :gen_tcp.send(sock, frame)
    {:noreply, state}
  end

  def handle_info({:tcp, sock, data}, state) do
    {:noreply, route_event(:json.decode(data), sock, state)}
  end

  def handle_info({:tcp_closed, sock}, state) do
    state = %{state | socks: Map.delete(state.socks, sock)}
    Logger.info("[rext] render backend disconnected (#{map_size(state.socks)} left)")
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    windows = for {id, p} <- state.windows, p != pid, into: %{}, do: {id, p}
    {:noreply, %{state | windows: windows}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internals ─────────────────────────────────────────────────────────────

  defp route_event(%{"t" => "event", "window" => window_id} = ev, _sock, state) do
    case state.windows[window_id] do
      nil ->
        Logger.warning("[rext] event for unknown window #{inspect(window_id)}")

      pid ->
        params = Map.take(ev, ["tag", "value"])
        Rext.Window.dispatch(pid, ev["event"] || "click", params)
    end

    state
  end

  # A renderer may name the window it draws. Binding it means later frames go
  # only to the renderer that wants them, instead of every window's frames
  # going to every renderer for client-side filtering.
  defp route_event(%{"t" => "hello"} = hello, sock, state) do
    target = hello["window"] || :all
    Logger.info("[rext] renderer hello: #{inspect(hello["renderer"])} window=#{inspect(target)}")
    put_in(state.socks[sock], target)
  end

  defp route_event(%{"t" => "described", "ref" => ref} = msg, _sock, state) do
    case Map.pop(state.pending, ref) do
      {nil, _} ->
        Logger.warning("[rext] described reply for unknown ref #{inspect(ref)}")
        state

      {from, pending} ->
        GenServer.reply(from, {:ok, msg["tree"]})
        %{state | pending: pending}
    end
  end

  defp route_event(_other, _sock, state), do: state

  # Send a frame to every renderer that wants it — the one bound to this window,
  # plus any that never announced. A send failure means the peer is gone before
  # its :tcp_closed arrived; drop it rather than keep retrying a dead socket.
  defp broadcast(state, frame, window_id) do
    Enum.reduce(state.socks, state, fn {sock, target}, acc ->
      if target == window_id or target == :all do
        case :gen_tcp.send(sock, frame) do
          :ok -> acc
          {:error, _} -> %{acc | socks: Map.delete(acc.socks, sock)}
        end
      else
        acc
      end
    end)
  end

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
