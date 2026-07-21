defmodule Rect.Test do
  @moduledoc """
  Remote inspection and interaction for a running rect app — the agent harness.

  Every function takes a `node` (and an optional window `id`, default `"main"`)
  and operates over Erlang distribution. Connect with `mix rect.connect`, then
  drive from IEx or from an agent via `:rpc.call/4`.

  Because the window's state and render tree are authoritative *on the BEAM*
  (the native backend only draws them), the whole logical harness works over
  dist with no round-trip to the renderer — you can read `tree/2` and `click/3`
  a window and verify the result even with no macOS app attached. Visual/pixel
  verification (a renderer-side screenshot) is a separate, additive step.

  This is the desktop counterpart to `Mob.Test`, and on desktop it's simpler and
  more reliable: the connection is local dist with no adb/simctl tunnels.

      node = :"rect_demo@127.0.0.1"

      Rect.Test.window(node)          #=> RectDemo.CounterWindow
      Rect.Test.assigns(node)         #=> %{count: 0}
      Rect.Test.tree(node)            #=> %{type: :column, ...}
      Rect.Test.find(node, "Count")   #=> [{[0], %{...}}]
      Rect.Test.click(node, :inc)     # drive the Increment button
      Rect.Test.assigns(node)         #=> %{count: 1}
  """

  import Kernel, except: [inspect: 2]
  alias Rect.Window

  @doc "The window's module."
  @spec window(node(), String.t()) :: module()
  def window(node, id \\ "main"), do: inspect(node, id).window

  @doc "The window's current assigns."
  @spec assigns(node(), String.t()) :: map()
  def assigns(node, id \\ "main"), do: inspect(node, id).assigns

  @doc "The window's current render tree."
  @spec tree(node(), String.t()) :: map()
  def tree(node, id \\ "main"), do: inspect(node, id).tree

  @doc "Full snapshot: `%{window:, id:, assigns:, tree:}`."
  @spec inspect(node(), String.t()) :: map()
  def inspect(node, id \\ "main") do
    :rpc.call(node, Window, :inspect, [Window.via(id)])
  end

  @doc """
  Find nodes whose `:text` or `:label` prop contains `substring`. Returns
  `{path, node}` tuples where `path` is the list of child indices from the root.
  """
  @spec find(node(), String.t(), String.t()) :: [{list(), map()}]
  def find(node, substring, id \\ "main") do
    search(tree(node, id), substring, [])
  end

  @doc """
  Click a control by its `on_click` tag — the desktop analogue of `Mob.Test.tap/2`.
  Synchronous: returns once the event is processed and the window re-rendered, so
  it's safe to read `assigns/2` immediately after.

      Rect.Test.click(node, :increment)
  """
  @spec click(node(), atom() | String.t(), String.t()) :: :ok
  def click(node, tag, id \\ "main") do
    :rpc.call(node, Window, :dispatch, [Window.via(id), "click", %{"tag" => to_string(tag)}])
  end

  @doc """
  Deliver a value-change event for a control by its `on_change` tag (e.g. a text
  field). Synchronous.
  """
  @spec input(node(), atom() | String.t(), String.t(), String.t()) :: :ok
  def input(node, tag, value, id \\ "main") do
    params = %{"tag" => to_string(tag), "value" => value}
    :rpc.call(node, Window, :dispatch, [Window.via(id), "change", params])
  end

  @doc "Whether a native render backend is currently attached."
  @spec connected?(node()) :: boolean()
  def connected?(node), do: :rpc.call(node, Rect.Bridge, :connected?, [])

  # ── internals ───────────────────────────────────────────────────────────────

  defp search(%{type: _} = node, sub, path) do
    props = Map.get(node, :props, %{})
    text = to_string(props[:text] || props[:label] || "")
    own = if String.contains?(text, sub), do: [{path, node}], else: []

    children =
      node
      |> Map.get(:children, [])
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, i} -> search(child, sub, path ++ [i]) end)

    own ++ children
  end

  defp search(_, _sub, _path), do: []
end
