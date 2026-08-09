defmodule Rext.PlatformTest do
  use ExUnit.Case, async: false

  alias Rext.Platform

  setup do
    on_exit(fn ->
      Application.delete_env(:rext, :platform)
      Application.delete_env(:rext, :backend)
    end)
  end

  test "platform detects the host OS when nothing is configured" do
    assert Platform.platform() in Platform.platforms()
  end

  test "config overrides the detected platform" do
    Application.put_env(:rext, :platform, :windows)
    assert Platform.platform() == :windows
  end

  test "backend defaults to the Compose baseline" do
    assert Platform.backend() == :compose
  end

  test "config overrides the backend" do
    Application.put_env(:rext, :backend, :winforms)
    assert Platform.backend() == :winforms
  end

  test "scope carries both axes" do
    Application.put_env(:rext, :platform, :linux)
    assert Platform.scope() == %{platform: :linux, backend: :compose}
  end

  test "platform and backend key sets are disjoint" do
    # Renderer splits props on the union of these; an overlap would make a
    # scope key ambiguous between the two axes.
    assert Platform.platforms() -- Platform.backends() == Platform.platforms()
  end
end
