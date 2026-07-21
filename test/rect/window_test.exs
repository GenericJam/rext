defmodule Rect.WindowTest do
  use ExUnit.Case, async: true

  alias Rect.Examples.CounterWindow
  alias Rect.Window

  # No bridge started: the window runs headless, which is exactly how the agent
  # harness inspects logical state without a native renderer attached.

  test "mount initializes assigns and inspect exposes the render tree" do
    {:ok, pid} = Window.start_link(CounterWindow, %{}, id: "t1", name: :win_t1)
    info = Window.inspect(pid)
    assert info.window == CounterWindow
    assert info.assigns == %{count: 0}
    assert info.tree.type == :column
  end

  test "dispatching click events drives handle_event and re-renders" do
    {:ok, pid} = Window.start_link(CounterWindow, %{}, id: "t2", name: :win_t2)

    :ok = Window.dispatch(pid, "click", %{"tag" => "inc"})
    :ok = Window.dispatch(pid, "click", %{"tag" => "inc"})
    assert Window.get_socket(pid).assigns.count == 2

    :ok = Window.dispatch(pid, "click", %{"tag" => "dec"})
    assert Window.get_socket(pid).assigns.count == 1
  end

  test "a NIF-delivered {:rect_ui_event, ...} routes to handle_event" do
    {:ok, pid} = Window.start_link(CounterWindow, %{}, id: "t3", name: :win_t3)

    send(pid, {:rect_ui_event, "click", %{"tag" => "inc"}})
    :sys.get_state(pid)
    assert Window.get_socket(pid).assigns.count == 1
  end
end
