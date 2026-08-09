defmodule Rext.Renderer do
  @moduledoc """
  Serializes a window's component tree into a transport-ready JSON frame.

  The render protocol is the contract between the BEAM and *any* render backend
  (SwiftUI on macOS today; Compose Multiplatform for Windows/Linux later; an
  in-process NIF host eventually). This module is intentionally
  transport-agnostic: it turns a tree into a normalized map + JSON binary and
  knows nothing about sockets, NIFs, or windows. `Rext.Bridge` owns the wire.

  ## Node format

      %{
        type: :column,
        props: %{spacing: :space_md, padding: :space_lg, background: :surface},
        children: [
          %{type: :text,   props: %{text: "Count: 0", font_size: 28, text_color: :on_surface}, children: []},
          %{type: :button, props: %{text: "Increment", on_click: :increment}, children: []}
        ]
      }

  Atom-valued color/background props resolve through `Rext.Theme`; `on_click` /
  `on_change` become the string event tag the backend echoes back on interaction.

  Prop names follow Compose + SwiftUI — see
  `decisions/2026-08-08-component-nomenclature.md`.

  ## Platform-scoped props

  A prop can be scoped to a platform (`:macos` / `:windows` / `:linux`) or to a
  backend (`:compose` / `:swiftui` / `:winforms`):

      props: %{padding: 12, macos: %{padding: 20}, winforms: %{corner_radius: 0}}

  Backends never see the scoped form — it's resolved here, against
  `Rext.Platform.scope/0`, before serialization. Precedence is
  unscoped < platform < backend: a backend override is the narrower claim
  ("WinForms specifically can't do this") and wins over a platform one.

  This is what keeps a capability gap from becoming a vocabulary amputation: a
  prop the weakest backend can't honor stays in the protocol, scoped, rather
  than being dropped from it for everyone.
  """

  alias Rext.Platform
  alias Rext.Theme

  # `text_color` is the foreground; `color` stays valid for single-color nodes
  # that have no text (divider, progress) where "the color" is unambiguous.
  @color_props ~w(text_color color background border_color)a
  @space_props ~w(spacing padding)a
  @event_props ~w(on_click on_change)a

  @scope_props Platform.platforms() ++ Platform.backends()

  @doc """
  Normalize a component tree into a JSON-safe map: string keys, platform-scoped
  props resolved, theme tokens resolved, event handlers reduced to their string
  tag.

  `scope` defaults to `Rext.Platform.scope/0`; pass one explicitly to normalize
  for a platform other than the host. Pure given a scope — the unit under test.
  """
  @spec normalize(map(), Platform.scope()) :: map()
  def normalize(node, scope \\ Platform.scope())

  def normalize(%{type: type} = node, scope) do
    props = node |> Map.get(:props, %{}) |> resolve_scopes(scope)
    children = Map.get(node, :children, [])

    %{
      "type" => to_string(type),
      "props" => normalize_props(props),
      "children" => Enum.map(children, &normalize(&1, scope))
    }
  end

  # Merge scoped overrides down onto the base props, most-specific last:
  # unscoped < platform-scoped < backend-scoped. A backend override is the
  # narrower statement ("WinForms specifically can't do this"), so it wins over
  # a platform one ("Windows generally wants this").
  defp resolve_scopes(props, scope) do
    {scoped, base} = Map.split(props, @scope_props)

    base
    |> merge_scope(Map.get(scoped, scope.platform))
    |> merge_scope(Map.get(scoped, scope.backend))
  end

  defp merge_scope(props, nil), do: props
  defp merge_scope(props, %{} = override), do: Map.merge(props, override)

  defp normalize_props(props) do
    Map.new(props, fn {k, v} -> {to_string(k), normalize_value(k, v)} end)
  end

  defp normalize_value(k, v) when k in @color_props, do: Theme.color(v)
  defp normalize_value(k, v) when k in @space_props, do: Theme.space(v)
  defp normalize_value(k, v) when k in @event_props, do: event_tag(v)
  defp normalize_value(_k, v), do: json_safe(v)

  # Accept both a bare tag atom (`on_click: :increment`) and mob's
  # `{pid, tag}` shape (`on_click: {self(), :increment}`) — we only need the tag,
  # since the bridge routes events back to a window by id.
  defp event_tag({_pid, tag}), do: to_string(tag)
  defp event_tag(tag) when is_atom(tag) or is_binary(tag), do: to_string(tag)

  defp json_safe(v) when is_atom(v) and v not in [true, false, nil], do: to_string(v)
  defp json_safe(v) when is_list(v), do: Enum.map(v, &json_safe/1)
  defp json_safe(%{} = v), do: Map.new(v, fn {k, val} -> {to_string(k), json_safe(val)} end)
  defp json_safe(v), do: v

  @doc """
  Render a tree to a JSON binary frame for a given window id. This is what the
  bridge puts on the wire (or, later, hands to the render NIF).
  """
  @spec frame(String.t(), map(), Platform.scope()) :: binary()
  def frame(window_id, tree, scope \\ Platform.scope()) do
    %{"t" => "render", "window" => window_id, "tree" => normalize(tree, scope)}
    |> :json.encode()
    |> IO.iodata_to_binary()
  end
end
