defmodule Rect.BridgeTest do
  use ExUnit.Case, async: false

  alias Rect.Examples.CounterWindow
  alias Rect.Window

  # Full socket-transport round-trip against the running bridge: a raw TCP
  # client (matching the Swift renderer's 4-byte framing) receives a render
  # frame and drives a click back into the window.

  setup do
    {:ok, pid} = Window.start_link(CounterWindow, %{}, id: "bridgetest", name: :win_bridge)
    port = Rect.Bridge.port()

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

  test "resolve_port/0 precedence: RECT_PORT env > config > default" do
    orig_env = System.get_env("RECT_PORT")
    orig_cfg = Application.get_env(:rect, :port)

    on_exit(fn ->
      if orig_env, do: System.put_env("RECT_PORT", orig_env), else: System.delete_env("RECT_PORT")

      if is_nil(orig_cfg),
        do: Application.delete_env(:rect, :port),
        else: Application.put_env(:rect, :port, orig_cfg)
    end)

    System.delete_env("RECT_PORT")
    Application.delete_env(:rect, :port)
    assert Rect.Bridge.resolve_port() == Rect.Bridge.default_port()

    Application.put_env(:rect, :port, 4321)
    assert Rect.Bridge.resolve_port() == 4321

    System.put_env("RECT_PORT", "5678")
    assert Rect.Bridge.resolve_port() == 5678
  end

  test "a busy port falls back to an ephemeral one instead of crashing the app" do
    {:ok, blocker} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}])
    {:ok, busy} = :inet.port(blocker)
    on_exit(fn -> :gen_tcp.close(blocker) end)

    {:ok, pid} = Rect.Bridge.start_link(port: busy, name: :bridge_fallback_test)
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
end
