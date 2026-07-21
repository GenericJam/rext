defmodule Rect.RendererTest do
  use ExUnit.Case, async: true

  alias Rect.Renderer

  test "normalize converts types/keys to strings and keeps structure" do
    tree = %{
      type: :column,
      props: %{gap: :space_md},
      children: [
        %{type: :text, props: %{text: "hi"}, children: []}
      ]
    }

    assert %{
             "type" => "column",
             "props" => %{"gap" => 16},
             "children" => [%{"type" => "text", "props" => %{"text" => "hi"}, "children" => []}]
           } = Renderer.normalize(tree)
  end

  test "normalize resolves color and background tokens through the theme" do
    node = %{type: :box, props: %{color: :primary, background: :surface}, children: []}
    %{"props" => props} = Renderer.normalize(node)
    assert props["color"] == "#7c5cff"
    assert props["background"] == "#2a2a38"
  end

  test "normalize reduces on_click to its string tag (bare atom or {pid, tag})" do
    bare = %{type: :button, props: %{on_click: :save}, children: []}
    tupled = %{type: :button, props: %{on_click: {self(), :save}}, children: []}
    assert Renderer.normalize(bare)["props"]["on_click"] == "save"
    assert Renderer.normalize(tupled)["props"]["on_click"] == "save"
  end

  test "frame produces a render envelope that round-trips through JSON" do
    tree = %{type: :text, props: %{text: "x"}, children: []}
    bin = Renderer.frame("main", tree)
    decoded = :json.decode(bin)
    assert decoded["t"] == "render"
    assert decoded["window"] == "main"
    assert decoded["tree"]["type"] == "text"
  end
end
