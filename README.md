# Rect

BEAM-on-desktop UI framework for Elixir — mob's desktop sibling.

> **Status:** Prototype. The programming model and agent harness are verified
> end-to-end on macOS (SwiftUI render backend over a socket). See
> `decisions/2026-07-20-rect-prototype-architecture.md`.

## What it is

You write Elixir. A unit of UI is a `Rect.Window` — one supervised GenServer
that produces a component tree. The tree is serialized and drawn by a native
render backend (SwiftUI on macOS; Compose Multiplatform for Windows/Linux is the
planned path, mirroring mob's SwiftUI + Compose split). Events come back over the
same channel. Because window state lives on the BEAM, you connect over Erlang
distribution to inspect and drive a running app — no rebuild, no restart.

This is mob's programming model, committed to desktop paradigm and concerns:
the unit is a **window**, apps run **many** at once, and there's no mobile
navigation stack — "another view" is "another window", i.e. another process.

```elixir
defmodule MyApp.CounterWindow do
  use Rect.Window

  def mount(_params, socket), do: {:ok, Rect.Socket.assign(socket, :count, 0)}

  def render(assigns) do
    %{type: :column, props: %{gap: :space_lg, padding: :space_xl},
      children: [
        %{type: :text,   props: %{text: "Count: #{assigns.count}", size: 34}, children: []},
        %{type: :button, props: %{label: "Increment", on_click: :inc}, children: []}
      ]}
  end

  def handle_event("click", %{"tag" => "inc"}, socket),
    do: {:noreply, Rect.Socket.update(socket, :count, &(&1 + 1))}
end
```

## Packages

| Package    | Role |
|------------|------|
| `rect`     | Runtime library, ships in the app: `Rect.Window`, `Rect.Socket`, `Rect.Renderer`, `Rect.Transport` (+ `Rect.Bridge`/`Rect.NifBridge`), `Rect.Theme`, `Rect.Test`. |
| `rect_dev` | Dev + agent tooling (never a shipped dependency): `mix rect.run`, `mix rect.connect`, and the MCP server (planned). |
| `rect_new` | Project generator: `mix rect.new my_app` (emits `.mcp.json` for agent sessions). |

## Render transports

The `Rect.Transport` seam supports two backends behind an identical programming
model (config: `config :rect, :transport, …`):

- **`Rect.NifBridge`** — in-process, the mob-faithful path: a native host binary
  owns `main()`, embeds the BEAM (stock OTP's `libbeam.a`, no custom build), and
  bridges via the `rect_nif` NIF. Built and verified in `native/macos/host`
  (`build.sh` → `rect_host`); see `decisions/2026-07-20-in-process-nif-host.md`.
- **`Rect.Bridge`** — out-of-process, a renderer connected over a socket. The
  "Port partner" model; also the path to a browser/remote renderer.

### Render port

The socket bridge's port is resolved highest-precedence-first:

1. **CLI** — `mix rect.run --port 9000` (sets `RECT_PORT` for that run)
2. **Project config** — `config :rect, :port, 9000`
3. **Default** — `8137`

If the resolved port is already in use, the bridge logs a warning and falls back
to an OS-assigned port rather than crashing — so a second instance never takes
down the first. (The dev launcher reads the actual port back, so the renderer
still connects.)

## Try it

```bash
# build the macOS render backend
(cd native/macos && ./build.sh)

# boot a named node with the counter window + renderer
elixir --name rect_demo@127.0.0.1 --cookie rect_secret -S mix run --no-halt dev/demo.exs
```

Then, from another terminal, drive it as an agent would — over dist, no UI:

```elixir
node = :"rect_demo@127.0.0.1"
Node.connect(node)
Rect.Test.window(node)     #=> Rect.Examples.CounterWindow
Rect.Test.assigns(node)    #=> %{count: 0}
Rect.Test.click(node, :inc)
Rect.Test.assigns(node)    #=> %{count: 1}
```

> The native window renders in your GUI session. If you launch the renderer from
> a shell detached from the Aqua login session it will connect and decode frames
> but not display — that's a session limitation, not a framework one.

## Agent harness

`Rect.Test` is the front door for agent-driven development, over local dist:
`window/1`, `assigns/1`, `tree/1`, `find/2`, `click/2`, `input/3`, `connected?/1`.
Window state and the render tree are authoritative on the BEAM, so the whole
logical harness works with or without a native renderer attached.

## License

MIT
