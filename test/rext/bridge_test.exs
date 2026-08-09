defmodule Rext.BridgeTest do
  use ExUnit.Case, async: false

  alias Rext.Examples.CounterWindow
  alias Rext.Window

  # Full socket-transport round-trip against the running bridge: a raw TCP
  # client (matching the Swift renderer's 4-byte framing) receives a render
  # frame and drives a click back into the window.

  # start_supervised! rather than start_link: every test here registers the same
  # :win_bridge name, and ExUnit guarantees a supervised child is down before the
  # next test starts. A linked window is not guaranteed to be — a `:normal` exit
  # from the test process doesn't kill a non-trapping child — so the survivor
  # would hold the name and every subsequent setup fails with :already_started.
  setup do
    pid =
      start_supervised!(%{
        id: :win_bridge,
        start: {Window, :start_link, [CounterWindow, %{}, [id: "bridgetest", name: :win_bridge]]}
      })

    port = Rext.Bridge.port()

    {:ok, sock} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 4, active: false])

    on_exit(fn -> :gen_tcp.close(sock) end)
    %{window: pid, sock: sock}
  end

  test "renderer receives a render frame on connect", %{sock: sock} do
    frame = recv_frame_for(sock, "bridgetest")
    assert frame["t"] == "render"
    assert frame["window"] == "bridgetest"
    assert frame["tree"]["type"] == "column"
  end

  test "an event frame from the renderer drives handle_event", %{sock: sock, window: pid} do
    # Drain the initial flush so the socket is at a clean point.
    _ = recv_frame_for(sock, "bridgetest")

    ev = %{"t" => "event", "window" => "bridgetest", "event" => "click", "tag" => "inc"}
    :ok = :gen_tcp.send(sock, :json.encode(ev))

    assert eventually(fn -> Window.get_socket(pid).assigns.count == 1 end)
  end

  test "resolve_port/0 precedence: REXT_PORT env > config > default" do
    orig_env = System.get_env("REXT_PORT")
    orig_cfg = Application.get_env(:rext, :port)

    on_exit(fn ->
      if orig_env, do: System.put_env("REXT_PORT", orig_env), else: System.delete_env("REXT_PORT")

      if is_nil(orig_cfg),
        do: Application.delete_env(:rext, :port),
        else: Application.put_env(:rext, :port, orig_cfg)
    end)

    System.delete_env("REXT_PORT")
    Application.delete_env(:rext, :port)
    assert Rext.Bridge.resolve_port() == Rext.Bridge.default_port()

    Application.put_env(:rext, :port, 4321)
    assert Rext.Bridge.resolve_port() == 4321

    System.put_env("REXT_PORT", "5678")
    assert Rext.Bridge.resolve_port() == 5678
  end

  test "a busy port falls back to an ephemeral one instead of crashing the app" do
    {:ok, blocker} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, busy} = :inet.port(blocker)
    on_exit(fn -> :gen_tcp.close(blocker) end)

    {:ok, pid} = Rext.Bridge.start_link(port: busy, name: :bridge_fallback_test)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.alive?(pid)
    fallback_port = GenServer.call(:bridge_fallback_test, :port)
    assert fallback_port != busy
    assert fallback_port > 0
  end

  # Read framed JSON objects until one targets `window_id` (the flush may carry
  # frames for other windows registered with the shared bridge).
  defp recv_frame_for(sock, window_id, tries \\ 20)
  defp recv_frame_for(_sock, _window_id, 0), do: flunk("no frame for window arrived")

  defp recv_frame_for(sock, window_id, tries) do
    {:ok, data} = :gen_tcp.recv(sock, 0, 2000)
    frame = :json.decode(data)

    if frame["window"] == window_id, do: frame, else: recv_frame_for(sock, window_id, tries - 1)
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end

  describe "many renderers, many windows" do
    setup do
      other =
        start_supervised!(%{
          id: :win_second,
          start: {Window, :start_link, [CounterWindow, %{}, [id: "second", name: :win_second]]}
        })

      %{other: other}
    end

    test "two renderers each receive only their own window's frames", %{sock: a} do
      {:ok, b} =
        :gen_tcp.connect(~c"127.0.0.1", Rext.Bridge.port(), [:binary, packet: 4, active: false])

      on_exit(fn -> :gen_tcp.close(b) end)

      # Announce which window each draws. Until a renderer says, it is sent
      # everything and filters client-side.
      announce(a, "bridgetest")
      announce(b, "second")

      # On connect a renderer is flushed every window's latest frame — it hasn't
      # said which one it draws yet. Drain that backlog so what follows is only
      # what the bridge chose to route after the bind.
      drain(a)
      drain(b)

      # A render on one window must not reach the other window's renderer.
      :ok = Window.dispatch(:win_bridge, "click", %{"tag" => "inc"})

      assert recv_frame_for(a, "bridgetest")["t"] == "render"
      assert {:error, :timeout} = :gen_tcp.recv(b, 0, 200)
    end

    test "a second renderer does not displace the first", %{sock: a} do
      {:ok, b} =
        :gen_tcp.connect(~c"127.0.0.1", Rext.Bridge.port(), [:binary, packet: 4, active: false])

      on_exit(fn -> :gen_tcp.close(b) end)
      announce(b, "second")
      drain(a)

      # The bug this fixes: the bridge kept one socket, so connecting `b`
      # silently orphaned `a` and the first window went dark.
      :ok = Window.dispatch(:win_bridge, "click", %{"tag" => "inc"})
      assert recv_frame_for(a, "bridgetest")["t"] == "render"
    end
  end

  describe "describe round-trip (native tree)" do
    test "no renderer bound to the window" do
      assert Rext.Bridge.describe("nobody", 200) == {:error, :no_renderer}
    end

    test "the bridge relays the renderer's own description of what it built" do
      %{sock: sock} = announce_and_drain("bridgetest")

      task = Task.async(fn -> Rext.Bridge.describe("bridgetest", 2_000) end)

      # Stand in for a backend: answer the describe with a tree that
      # deliberately differs from what the BEAM sent, so a pass can only come
      # from the reply and not from the bridge echoing its own state.
      assert {:ok, req} = :gen_tcp.recv(sock, 0, 1_000)
      req = :json.decode(req)
      assert req["t"] == "describe"
      assert req["window"] == "bridgetest"

      reply = %{
        "t" => "described",
        "window" => "bridgetest",
        "ref" => req["ref"],
        "tree" => %{"kind" => "NSStackView", "label" => nil, "children" => []}
      }

      :gen_tcp.send(sock, :json.encode(reply))

      assert {:ok, %{"kind" => "NSStackView"}} = Task.await(task)
    end

    test "a renderer that never answers times out rather than hanging" do
      %{sock: _} = announce_and_drain("bridgetest")
      assert Rext.Bridge.describe("bridgetest", 300) == {:error, :timeout}
    end
  end

  # A raw socket bound to `window`, with its connect-time frame backlog drained.
  defp announce_and_drain(window) do
    {:ok, sock} =
      :gen_tcp.connect(~c"127.0.0.1", Rext.Bridge.port(), [:binary, packet: 4, active: false])

    on_exit(fn -> :gen_tcp.close(sock) end)
    announce(sock, window)
    drain(sock)
    %{sock: sock}
  end

  defp drain(sock) do
    case :gen_tcp.recv(sock, 0, 100) do
      {:ok, _} -> drain(sock)
      {:error, :timeout} -> :ok
    end
  end

  defp announce(sock, window) do
    :gen_tcp.send(sock, :json.encode(%{"t" => "hello", "renderer" => "test", "window" => window}))
    # The bind is a cast from the bridge's perspective; make sure it lands
    # before asserting on routing.
    _ = Rext.Bridge.renderers()
    :ok
  end
end
