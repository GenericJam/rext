defmodule Rext.SocketTest do
  use ExUnit.Case, async: true

  alias Rext.Socket

  test "new/2 sets window metadata from opts" do
    s = Socket.new(SomeWindow, id: "w1", title: "Hi", size: {800, 600})
    assert s.__rext__.window == SomeWindow
    assert Socket.id(s) == "w1"
    assert s.__rext__.title == "Hi"
    assert s.__rext__.size == {800, 600}
  end

  test "new/2 applies defaults" do
    s = Socket.new(SomeWindow)
    assert Socket.id(s) == "main"
    assert s.__rext__.title == "Rext"
  end

  test "assign/3 and assign/2 write into assigns" do
    s = Socket.new(W) |> Socket.assign(:a, 1) |> Socket.assign(b: 2, c: 3)
    assert s.assigns == %{a: 1, b: 2, c: 3}
  end

  test "update/3 applies a function to an existing assign" do
    s = Socket.new(W) |> Socket.assign(:n, 10) |> Socket.update(:n, &(&1 * 2))
    assert s.assigns.n == 20
  end

  test "update/3 raises on a missing key" do
    assert_raise KeyError, fn -> Socket.update(Socket.new(W), :missing, & &1) end
  end

  test "assign_new/3 computes only when absent" do
    s = Socket.new(W) |> Socket.assign(:x, 1) |> Socket.assign_new(:x, fn -> 99 end)
    assert s.assigns.x == 1
    s2 = Socket.assign_new(s, :y, fn -> 7 end)
    assert s2.assigns.y == 7
  end

  test "put_rext/3 updates internal metadata without touching assigns" do
    s = Socket.new(W) |> Socket.assign(:a, 1) |> Socket.put_rext(:tree, %{type: :text})
    assert s.__rext__.tree == %{type: :text}
    assert s.assigns == %{a: 1}
  end
end
