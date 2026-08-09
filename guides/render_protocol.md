# rext render protocol

The contract between the BEAM and a **render backend**. Any backend (SwiftUI,
Compose, WinUI, a browser, …) that speaks this protocol is a valid rext renderer.
This is the surface a new backend — or a parallel Claude instance on another
platform — implements against. The macOS SwiftUI renderer
(`native/macos/main.swift`) is the reference implementation.

## Model

- The BEAM owns state and layout. Each `Rext.Window` produces a **render tree**;
  `Rext.Renderer` normalizes it to JSON and sends it to the backend.
- The backend **draws** the tree and sends **events** (clicks, input) back.
- One backend instance draws **one window** (`REXT_WINDOW`, default `"main"`); it
  ignores frames for other windows. A multi-window app runs one backend per window.
- Colors and spacing are **already resolved server-side** (hex strings, pixel
  numbers). A backend draws literal values — it does not need the theme.

## Transport

Two transports carry the identical message content:

- **Socket** (`Rext.Bridge`, out-of-process): TCP on `127.0.0.1:$REXT_PORT`,
  **4-byte big-endian length-prefixed** UTF-8 JSON frames (Erlang `{:packet, 4}`).
  Each frame: `[uint32 length N][N bytes JSON]`, both directions.
- **In-process NIF** (`Rext.NifBridge`): the same JSON handed to `rext_nif`
  directly; events return via `enif_send`. Used by the embedded-BEAM host.

A socket backend reads two env vars: `REXT_PORT` (where to connect) and
`REXT_WINDOW` (which window to draw; default `"main"`).

## Messages

All messages are JSON objects with a `"t"` type tag.

**Backend → BEAM, on connect (hello):**
```json
{"t": "hello", "renderer": "compose-desktop"}
```

**BEAM → backend (render a frame):**
```json
{"t": "render", "window": "main", "tree": { ...node... }}
```
The backend ignores frames whose `"window"` ≠ its `REXT_WINDOW`.

**Backend → BEAM (interaction event):**
```json
{"t": "event", "window": "main", "event": "click", "tag": "inc"}
```
- `event`: `"click"` (buttons) or `"change"` (inputs; carries `"value"`).
- `tag`: the control's `on_click` / `on_change` tag.
- `window`: the backend's target window id.

## Node format

```json
{"type": "column", "props": {"spacing": 24, "padding": 32, "background": "#1e1e28"},
 "children": [ ...nodes... ]}
```
Every node has string `type`, a `props` object (string keys), and `children`.

### Component catalog (current)

| type    | props | notes |
|---------|-------|-------|
| `column`| `spacing` (px int), `padding` (px int), `background` (hex) | vertical stack, leading-aligned |
| `row`   | `spacing`, `padding`, `background` | horizontal stack |
| `text`  | `text` (string), `font_size` (px int), `text_color` (hex) | |
| `button`| `text` (string), `on_click` (tag string), `background` (hex) | emits `click` with `tag`. `background` honored on SwiftUI only |
| `box`   | `padding`, `background` (hex), `corner_radius` (px int), `fill_width` (bool) | container. `corner_radius` accepted-and-ignored on WinForms — Win32 panels have none |
| `spacer`| `size` (px int) | fixed space; omit `size` to fill the remaining space along the parent's axis |
| `divider`| `color` (hex), `thickness` (px int, default 1) | horizontal rule |

Prop names follow Compose + SwiftUI — see
`decisions/2026-08-08-component-nomenclature.md` for the vocabulary and the
tiebreak order. `text` is the content a node displays; `label` is reserved for
the caption on a control that carries its own value (`toggle`, `slider`).

### Platform-scoped props

A prop can be scoped to a platform (`macos` / `windows` / `linux`) or to a
backend (`compose` / `swiftui` / `winforms`):

```elixir
props: %{padding: 12, macos: %{padding: 20}, winforms: %{corner_radius: 0}}
```

Precedence is unscoped < platform < backend — a backend override is the
narrower claim ("WinForms specifically can't do this") and wins over a platform
one ("Windows generally wants this").

**Backends never see the scoped form.** `Rext.Renderer` resolves it against
`Rext.Platform.scope/0` and strips the scope keys before serializing, so a
backend implements one flat prop set and nothing else. Two axes rather than
mob's one, because Compose is the baseline on *every* platform and the native
backends are an opt-in upgrade on top — so "which OS" and "which backend" are
genuinely different questions here.

This is what keeps a capability gap from becoming a vocabulary amputation: a
prop the weakest backend can't honor stays in the protocol, scoped, rather than
being removed from it for everyone.

Planned: `text_field` (`value`, `placeholder`, `on_change` tag → `change` events).

Unknown `type`s should render their `children` in a plain container (forward-compat).

## Lifecycle

1. Backend connects, sends `hello`, starts reading frames.
2. On each `render` frame for its window, it redraws.
3. Closing the window → the backend process exits.
4. On the socket transport under `mix rext.run`, the backend exiting halts the
   BEAM (no residual node); losing the connection (BEAM gone) → the backend exits.
   So the two lifetimes are tied in both directions.

## Reference & conformance

- Reference: `native/macos/main.swift` (socket, SwiftUI). Read it alongside this
  spec — it exercises every message and the framing.
- A backend "works" only after a **human sees its window render correctly on a
  real, arch-matched display** (see `PLAN.md` → verification frontier). A green
  build is necessary, not sufficient.
