defmodule Rext.Embedded do
  @moduledoc """
  Boot entry for the in-process host. The native host binary owns `main()`,
  boots the embedded BEAM on a background thread, and evaluates
  `Rext.Embedded.start()` — mirroring how mob's iOS app calls `App:start()`
  after ERTS comes up.

  Selects the NIF transport, starts the rext application, and opens the demo
  window. The window then renders through the NIF instead of a socket.
  """
  require Logger

  @doc "Boot the in-process demo: NIF transport + counter window."
  @spec start() :: :ok
  def start do
    Application.put_env(:rext, :transport, Rext.NifBridge)
    {:ok, _} = Application.ensure_all_started(:rext)
    {:ok, _} = Rext.open(Rext.Examples.CounterWindow, id: "main", title: "Counter")
    Logger.info("[rext.embedded] started with NIF transport")
    :ok
  end
end
