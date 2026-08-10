defmodule Rext.Catalog do
  @moduledoc """
  The component catalog: which node types exist and which props each accepts.

  One source of truth for what `guides/render_protocol.md` documents and what
  the backends implement. Its job is diagnostics, not enforcement — a misspelled
  prop is *reported*, never dropped, because a newer backend may understand a
  prop this BEAM has never heard of and silently eating it would be worse than
  the typo.

  Unknown **node types** are not an error at all: the protocol requires backends
  to render an unknown type's children in a plain container, and that
  forward-compat path is deliberate. Only props on a *known* type are checked,
  since that's where a typo is unambiguous.
  """

  # Valid on every node type.
  @universal ~w(accessibility_label)a

  # Scope containers, not props — they hold a map of props for one platform or
  # backend and are resolved away before serialization. Valid on any node.
  @scopes Rext.Platform.platforms() ++ Rext.Platform.backends()

  @types %{
    column: ~w(spacing padding background)a,
    row: ~w(spacing padding background)a,
    text: ~w(text font_size text_color)a,
    button: ~w(text on_click background)a,
    box: ~w(padding background corner_radius fill_width)a,
    spacer: ~w(size)a,
    divider: ~w(color thickness)a,
    text_field: ~w(value placeholder on_change on_submit secure background text_color
                   placeholder_color border_color padding corner_radius)a
  }

  @doc "Every node type in the catalog."
  @spec types() :: [atom()]
  def types, do: Map.keys(@types)

  @doc "Props valid on every node type."
  @spec universal() :: [atom()]
  def universal, do: @universal

  @doc "Props accepted by `type`, or `nil` if the type isn't in the catalog."
  @spec props(atom()) :: [atom()] | nil
  def props(type), do: Map.get(@types, type)

  @doc """
  Every `{type, prop}` in a tree that the catalog doesn't recognize.

  Pure — walks the tree and reports. Nodes of unknown *type* are skipped (their
  props can't be judged), but their children are still walked.
  """
  @spec unknown_props(map()) :: [{atom(), atom()}]
  def unknown_props(node) when is_map(node) do
    node |> collect([]) |> Enum.uniq()
  end

  defp collect(%{type: type} = node, acc) do
    acc =
      case props(type) do
        nil ->
          acc

        known ->
          allowed = known ++ @universal ++ @scopes

          node
          |> Map.get(:props, %{})
          |> Map.keys()
          |> Enum.reject(&(&1 in allowed))
          |> Enum.map(&{type, &1})
          |> Kernel.++(acc)
      end

    node
    |> Map.get(:children, [])
    |> Enum.reduce(acc, &collect/2)
  end

  defp collect(_not_a_node, acc), do: acc
end
