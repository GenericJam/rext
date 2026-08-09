defmodule Rext.Platform do
  @moduledoc """
  Which platform and render backend a tree is being rendered for.

  This is what `Rext.Renderer` resolves platform-scoped props against. Two
  independent axes, because desktop has both and they differ:

    * **platform** (`:macos` / `:windows` / `:linux`) — an OS concern. Where the
      menu bar lives is a platform question; both backends on that OS answer it
      the same way.
    * **backend** (`:compose` / `:swiftui` / `:winforms`) — a capability
      concern. Whether a switch control exists is a backend question; Compose
      and SwiftUI can draw one on the same OS where WinForms cannot.

  mob only needs the first axis (one backend per mobile platform). rext needs
  both, since Compose is the baseline *everywhere* and the native backends are
  an opt-in upgrade on top of it.

  Both are overridable from config, which is also how tests pin a scope:

      config :rext, :platform, :windows
      config :rext, :backend, :winforms
  """

  @platforms ~w(macos windows linux)a
  @backends ~w(compose swiftui winforms)a

  @type platform :: :macos | :windows | :linux
  @type backend :: :compose | :swiftui | :winforms
  @type scope :: %{platform: platform(), backend: backend()}

  @doc "Every recognized platform scope key."
  @spec platforms() :: [platform()]
  def platforms, do: @platforms

  @doc "Every recognized backend scope key."
  @spec backends() :: [backend()]
  def backends, do: @backends

  @doc "The platform being rendered for — config override, else the host OS."
  @spec platform() :: platform()
  def platform, do: Application.get_env(:rext, :platform) || detect()

  @doc """
  The backend being rendered for.

  Defaults to `:compose` — the baseline that runs on all three platforms, and
  the safe assumption when nothing has told us otherwise. A connected renderer
  announces itself in its `hello` frame; wiring that through to here so the
  scope reflects the *actual* attached backend is a follow-up.
  """
  @spec backend() :: backend()
  def backend, do: Application.get_env(:rext, :backend, :compose)

  @doc "The full scope a tree is normalized against."
  @spec scope() :: scope()
  def scope, do: %{platform: platform(), backend: backend()}

  defp detect do
    case :os.type() do
      {:unix, :darwin} -> :macos
      {:win32, _} -> :windows
      _ -> :linux
    end
  end
end
