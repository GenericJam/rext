defmodule Rext.RendererTest do
  use ExUnit.Case, async: true

  alias Rext.Renderer

  test "normalize converts types/keys to strings and keeps structure" do
    tree = %{
      type: :column,
      props: %{spacing: :space_md},
      children: [
        %{type: :text, props: %{text: "hi"}, children: []}
      ]
    }

    assert %{
             "type" => "column",
             "props" => %{"spacing" => 16},
             "children" => [%{"type" => "text", "props" => %{"text" => "hi"}, "children" => []}]
           } = Renderer.normalize(tree)
  end

  test "normalize resolves color and background tokens through the theme" do
    node = %{type: :box, props: %{color: :primary, background: :surface}, children: []}
    %{"props" => props} = Renderer.normalize(node)
    assert props["color"] == "#7c5cff"
    assert props["background"] == "#2a2a38"
  end

  test "normalize resolves text_color, the foreground prop" do
    node = %{type: :text, props: %{text: "hi", text_color: :on_surface}, children: []}
    assert Renderer.normalize(node)["props"]["text_color"] == "#e8e8f0"
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

  describe "platform-scoped props" do
    @mac %{platform: :macos, backend: :swiftui}
    @win %{platform: :windows, backend: :winforms}

    test "a platform scope overrides the unscoped value, and is stripped from the frame" do
      node = %{type: :box, props: %{padding: 12, macos: %{padding: 20}}, children: []}

      assert Renderer.normalize(node, @mac)["props"] == %{"padding" => 20}
      assert Renderer.normalize(node, @win)["props"] == %{"padding" => 12}
    end

    test "a backend scope beats a platform scope — the narrower claim wins" do
      node = %{
        type: :toggle,
        props: %{corner_radius: 8, windows: %{corner_radius: 4}, winforms: %{corner_radius: 0}},
        children: []
      }

      assert Renderer.normalize(node, @win)["props"] == %{"corner_radius" => 0}
    end

    test "scoped props resolve through the theme like any other prop" do
      node = %{
        type: :text,
        props: %{text_color: :muted, macos: %{text_color: :primary}},
        children: []
      }

      assert Renderer.normalize(node, @mac)["props"]["text_color"] == "#7c5cff"
      assert Renderer.normalize(node, @win)["props"]["text_color"] == "#9a9ab0"
    end

    test "a scope can add a prop the base doesn't have" do
      node = %{type: :box, props: %{padding: 4, winforms: %{background: :surface}}, children: []}

      assert Renderer.normalize(node, @win)["props"] == %{
               "padding" => 4,
               "background" => "#2a2a38"
             }
    end

    test "scopes resolve at every depth, not just the root" do
      node = %{
        type: :column,
        props: %{spacing: 8},
        children: [%{type: :text, props: %{text: "hi", macos: %{text: "hello"}}, children: []}]
      }

      [child] = Renderer.normalize(node, @mac)["children"]
      assert child["props"]["text"] == "hello"
    end
  end

  describe "container and layout components" do
    test "box props survive normalization, including the WinForms-ignored one" do
      node = %{
        type: :box,
        props: %{padding: :space_md, background: :surface, corner_radius: 8, fill_width: true},
        children: [%{type: :text, props: %{text: "in a box"}, children: []}]
      }

      %{"props" => props, "children" => [child]} = Renderer.normalize(node)

      assert props == %{
               "padding" => 16,
               "background" => "#2a2a38",
               "corner_radius" => 8,
               "fill_width" => true
             }

      assert child["props"]["text"] == "in a box"
    end

    test "a spacer with no size stays sizeless — the backend reads that as 'fill'" do
      assert Renderer.normalize(%{type: :spacer, props: %{}, children: []})["props"] == %{}

      assert Renderer.normalize(%{type: :spacer, props: %{size: 16}, children: []})["props"] == %{
               "size" => 16
             }
    end

    test "divider resolves its color token" do
      node = %{type: :divider, props: %{color: :border, thickness: 2}, children: []}
      assert Renderer.normalize(node)["props"] == %{"color" => "#3a3a4a", "thickness" => 2}
    end
  end
end
