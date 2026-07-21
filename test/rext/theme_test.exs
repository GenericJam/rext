defmodule Rext.ThemeTest do
  use ExUnit.Case, async: true

  alias Rext.Theme

  test "color/1 resolves known tokens to hex" do
    assert Theme.color(:primary) == "#7c5cff"
    assert Theme.color(:background) == "#1e1e28"
  end

  test "color/1 passes hex strings through and falls back for unknown atoms" do
    assert Theme.color("#abcdef") == "#abcdef"
    assert Theme.color(:no_such_token) == "#000000"
  end

  test "space/1 resolves spacing tokens and passes numbers through" do
    assert Theme.space(:space_md) == 16
    assert Theme.space(:space_xl) == 32
    assert Theme.space(12) == 12
    assert Theme.space(:no_such_token) == 0
  end
end
