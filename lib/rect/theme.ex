defmodule Rect.Theme do
  @moduledoc """
  Minimal design-token resolution for the prototype.

  The renderer resolves atom-valued color/spacing tokens through this module so
  window code can say `color: :on_surface` instead of a raw hex string. This is
  a deliberately small copy of mob's much larger theme system — enough to prove
  the token-resolution seam exists on the desktop side. When rect's core is
  eventually lifted into a shared package with mob, this is one of the modules
  that merges.
  """

  @colors %{
    background: "#1e1e28",
    surface: "#2a2a38",
    on_background: "#f0f0f5",
    on_surface: "#e8e8f0",
    primary: "#7c5cff",
    on_primary: "#ffffff",
    muted: "#9a9ab0",
    border: "#3a3a4a"
  }

  @spacing %{space_xs: 4, space_sm: 8, space_md: 16, space_lg: 24, space_xl: 32}

  @doc "Resolve a color token (atom) to a hex string. Passes through hex strings."
  @spec color(atom() | String.t()) :: String.t()
  def color(token) when is_atom(token), do: Map.get(@colors, token, "#000000")
  def color("#" <> _ = hex), do: hex
  def color(other) when is_binary(other), do: other

  @doc "Resolve a spacing token (atom) to a number. Passes through numbers."
  @spec space(atom() | number()) :: number()
  def space(token) when is_atom(token), do: Map.get(@spacing, token, 0)
  def space(n) when is_number(n), do: n
end
