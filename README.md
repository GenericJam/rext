# Rext

BEAM-on-desktop UI framework for Elixir — mob's desktop sibling.

> **Status:** Prototype, actively built. Programming model + agent harness proven;
> a **Compose Desktop** baseline renderer runs on macOS/Windows/Linux (visually
> verified on macOS + Linux), with **native** backends alongside it: SwiftUI
> (macOS, verified) and WinForms (Windows, CI-compiling). See `PLAN.md`.

## What it is

You write Elixir. A unit of UI is a `Rext.Window` — one supervised GenServer
that produces a component tree. The tree is serialized and drawn by a native
render backend, and events come back over the same channel. Because window state
lives on the BEAM, you connect over Erlang distribution to inspect and drive a
running app — no rebuild, no restart.

The renderer is pluggable (see `guides/render_protocol.md`). Today: a **Compose
Multiplatform** baseline for consistent styling everywhere (`native/compose`),
plus opt-in **native** backends — **SwiftUI** on macOS (`native/macos`) and
**WinForms** on Windows (`native/windows`). The value proposition and the
five-backend strategy (native feel + BEAM + agentic coding) live in `PLAN.md`.

This is mob's programming model, committed to desktop paradigm and concerns:
the unit is a **window**, apps run **many** at once, and there's no mobile
navigation stack — "another view" is "another window", i.e. another process.

```elixir
defmodule MyApp.CounterWindow do
  use Rext.Window

  def mount(_params, socket), do: {:ok, Rext.Socket.assign(socket, :count, 0)}

  def render(assigns) do
    %{type: :column, props: %{spacing: :space_lg, padding: :space_xl},
      children: [
        %{type: :text,   props: %{text: "Count: #{assigns.count}", font_size: 34}, children: []},
        %{type: :button, props: %{text: "Increment", on_click: :inc}, children: []}
      ]}
  end

  def handle_event("click", %{"tag" => "inc"}, socket),
    do: {:noreply, Rext.Socket.update(socket, :count, &(&1 + 1))}
end
```

## Packages

| Package    | Role |
|------------|------|
| `rext`     | Runtime library, ships in the app: `Rext.Window`, `Rext.Socket`, `Rext.Renderer`, `Rext.Transport` (+ `Rext.Bridge`/`Rext.NifBridge`), `Rext.Theme`, `Rext.Test`. |
| `rext_dev` | Dev + agent tooling (never a shipped dependency): `mix rext.run`, `mix rext.connect`. |
| `rext_new` | Project generator: `mix rext.new my_app`. |

## Render transports

The `Rext.Transport` seam supports two backends behind an identical programming
model (config: `config :rext, :transport, …`):

- **`Rext.NifBridge`** — in-process, the mob-faithful path: a native host binary
  owns `main()`, embeds the BEAM (stock OTP's `libbeam.a`, no custom build), and
  bridges via the `rext_nif` NIF. Built and verified in `native/macos/host`
  (`build.sh` → `rext_host`); see `decisions/2026-07-20-in-process-nif-host.md`.
- **`Rext.Bridge`** — out-of-process, a renderer connected over a socket. The
  "Port partner" model; also the path to a browser/remote renderer.

### Render port

The socket bridge's port is resolved highest-precedence-first:

1. **CLI** — `mix rext.run --port 9000` (sets `REXT_PORT` for that run)
2. **Project config** — `config :rext, :port, 9000`
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
elixir --name rext_demo@127.0.0.1 --cookie rext_secret -S mix run --no-halt dev/demo.exs
```

Then, from another terminal, drive it as an agent would — over dist, no UI:

```elixir
node = :"rext_demo@127.0.0.1"
Node.connect(node)
Rext.Test.window(node)     #=> Rext.Examples.CounterWindow
Rext.Test.assigns(node)    #=> %{count: 0}
Rext.Test.click(node, :inc)
Rext.Test.assigns(node)    #=> %{count: 1}
```

> The native window renders in your GUI session. If you launch the renderer from
> a shell detached from the Aqua login session it will connect and decode frames
> but not display — that's a session limitation, not a framework one.

## Agent harness

`Rext.Test` is the front door for agent-driven development, over local dist:
`window/1`, `assigns/1`, `tree/1`, `find/2`, `click/2`, `input/3`, `connected?/1`.
Window state and the render tree are authoritative on the BEAM, so the whole
logical harness works with or without a native renderer attached.

## License

MIT
