defmodule Rext.CatalogTest do
  use ExUnit.Case, async: true

  alias Rext.Catalog

  test "a well-formed tree reports nothing" do
    tree = %{
      type: :column,
      props: %{spacing: 8, padding: 4},
      children: [%{type: :text, props: %{text: "hi", font_size: 12}, children: []}]
    }

    assert Catalog.unknown_props(tree) == []
  end

  test "a misspelled prop is reported with its node type" do
    tree = %{type: :text, props: %{text: "hi", fontsize: 12}, children: []}
    assert Catalog.unknown_props(tree) == [{:text, :fontsize}]
  end

  test "a prop valid on one type is still wrong on another" do
    # `size` is a spacer prop; on text the equivalent is font_size.
    tree = %{type: :text, props: %{text: "hi", size: 12}, children: []}
    assert Catalog.unknown_props(tree) == [{:text, :size}]
  end

  test "universal props are valid everywhere" do
    for type <- Catalog.types() do
      tree = %{type: type, props: %{accessibility_label: "x"}, children: []}
      assert Catalog.unknown_props(tree) == [], "#{type} rejected a universal prop"
    end
  end

  test "scope containers are not mistaken for props" do
    tree = %{
      type: :box,
      props: %{padding: 4, macos: %{padding: 8}, winforms: %{corner_radius: 0}},
      children: []
    }

    assert Catalog.unknown_props(tree) == []
  end

  test "an unknown node type is not an error, but its children are still checked" do
    # Forward-compat: backends render unknown types' children in a plain
    # container, so a type this BEAM doesn't know is legitimate.
    tree = %{
      type: :some_future_thing,
      props: %{whatever: 1},
      children: [%{type: :text, props: %{nope: 1}, children: []}]
    }

    assert Catalog.unknown_props(tree) == [{:text, :nope}]
  end

  test "the same mistake in many places is reported once" do
    child = %{type: :text, props: %{txt: "a"}, children: []}
    tree = %{type: :column, props: %{}, children: [child, child, child]}

    assert Catalog.unknown_props(tree) == [{:text, :txt}]
  end

  test "every catalogued type is documented in the render protocol" do
    doc = File.read!("guides/render_protocol.md")

    for type <- Catalog.types() do
      assert doc =~ "`#{type}`", "#{type} is in the catalog but not in render_protocol.md"
    end
  end
end
