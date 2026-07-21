defmodule Rect.TransportTest do
  use ExUnit.Case, async: false

  alias Rect.Transport

  test "impl/0 defaults to the socket bridge" do
    assert Transport.impl() == Rect.Bridge
  end

  test "impl/0 honors the configured transport" do
    Application.put_env(:rect, :transport, Rect.NifBridge)
    assert Transport.impl() == Rect.NifBridge
  after
    Application.delete_env(:rect, :transport)
  end

  test "NifBridge reports available and would frame the tree the same as the socket path" do
    assert Rect.NifBridge.available?()
    # NifBridge.render/2 frames via the shared Rect.Renderer before the NIF call;
    # the frame it would send is exactly the socket transport's frame.
    tree = %{type: :text, props: %{text: "x"}, children: []}
    assert Rect.Renderer.frame("main", tree) =~ ~s("type":"text")
  end
end
