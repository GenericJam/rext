defmodule Rect.Renderer do
  @moduledoc """
  Serializes a window's component tree into a transport-ready JSON frame.

  The render protocol is the contract between the BEAM and *any* render backend
  (SwiftUI on macOS today; Compose Multiplatform for Windows/Linux later; an
  in-process NIF host eventually). This module is intentionally
  transport-agnostic: it turns a tree into a normalized map + JSON binary and
  knows nothing about sockets, NIFs, or windows. `Rect.Bridge` owns the wire.

  ## Node format

      %{
        type: :column,
        props: %{gap: :space_md, padding: :space_lg, background: :surface},
        children: [
          %{type: :text,   props: %{text: "Count: 0", size: 28, color: :on_surface}, children: []},
          %{type: :button, props: %{label: "Increment", on_click: :increment}, children: []}
        ]
      }

  Atom-valued color/background props resolve through `Rect.Theme`; `on_click` /
  `on_change` become the string event tag the backend echoes back on interaction.
  """

  alias Rect.Theme

  @color_props ~w(color background border_color)a
  @space_props ~w(gap padding)a
  @event_props ~w(on_click on_change)a

  @doc """
  Normalize a component tree into a JSON-safe map: string keys, resolved theme
  tokens, event handlers reduced to their string tag. Pure — the unit under test.
  """
  @spec normalize(map()) :: map()
  def normalize(%{type: type} = node) do
    props = Map.get(node, :props, %{})
    children = Map.get(node, :children, [])

    %{
      "type" => to_string(type),
      "props" => normalize_props(props),
      "children" => Enum.map(children, &normalize/1)
    }
  end

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
  @spec frame(String.t(), map()) :: binary()
  def frame(window_id, tree) do
    %{"t" => "render", "window" => window_id, "tree" => normalize(tree)}
    |> :json.encode()
    |> IO.iodata_to_binary()
  end
end
