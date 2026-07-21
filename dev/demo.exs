# Boot the counter demo: open the window process, and (unless RECT_HEADLESS=1)
# launch the macOS render backend as a child process pointed at the bridge port.
#
#   elixir --name rect_demo@127.0.0.1 --cookie rect_secret -S mix run --no-halt dev/demo.exs

{:ok, _pid} = Rect.open(Rect.Examples.CounterWindow, id: "main", title: "Counter")

port = Rect.Bridge.port()
IO.puts("[demo] bridge port #{port}; window opened")

unless System.get_env("RECT_HEADLESS") == "1" do
  bin = Path.join(File.cwd!(), "native/macos/rect_renderer")

  if File.exists?(bin) do
    Port.open({:spawn_executable, String.to_charlist(bin)}, [
      :binary,
      env: [{~c"RECT_PORT", String.to_charlist(Integer.to_string(port))}]
    ])

    IO.puts("[demo] launched render backend: #{bin}")
  else
    IO.puts("[demo] renderer binary not found (run native/macos/build.sh); headless")
  end
end
