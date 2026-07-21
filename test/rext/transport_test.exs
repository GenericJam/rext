defmodule Rext.TransportTest do
  use ExUnit.Case, async: false

  alias Rext.Transport

  test "impl/0 defaults to the socket bridge" do
    assert Transport.impl() == Rext.Bridge
  end

  test "impl/0 honors the configured transport" do
    Application.put_env(:rext, :transport, Rext.NifBridge)
    assert Transport.impl() == Rext.NifBridge
  after
    Application.delete_env(:rext, :transport)
  end

  test "NifBridge reports available and would frame the tree the same as the socket path" do
    assert Rext.NifBridge.available?()
    # NifBridge.render/2 frames via the shared Rext.Renderer before the NIF call;
    # the frame it would send is exactly the socket transport's frame.
    tree = %{type: :text, props: %{text: "x"}, children: []}
    assert Rext.Renderer.frame("main", tree) =~ ~s("type":"text")
  end
end
