# Multi-window rendering: many renderers on one bridge

- Date: 2026-08-09
- Status: accepted
- Closes the "one renderer draws one window" gap in
  `guides/desktop_surface_matrix.md` (§Window & chrome) and `PLAN.md` item 4.

## Context

rext's defining claim over mob is that the unit of UI is a *window* and apps run
*many* at once — "another view is another window, i.e. another process". The
BEAM side has always delivered that: windows are supervised GenServers, and
`rext_demo`'s Counter and Mirror genuinely sync by message passing, fully
drivable over dist.

The rendering did not. `Rext.Bridge` kept a single `sock`, so a second renderer
connecting **overwrote the first**: its socket stayed open but was never written
to again, and that window silently went dark. `mix rext.run` compounded it by
launching a renderer only for the app's primary window. So the headline claim
was true in the process model and unobservable on screen.

## What was already right

Worth recording, because it made this far smaller than it looked. All three
backends were already built for this:

- each takes `REXT_WINDOW` and knows the single window it draws;
- each **filters incoming render frames** by that window
  (`obj.optString("window") == target` and equivalents);
- each **tags outgoing events** with it.

The protocol was already window-addressed too — every frame carries
`"window"`. The entire gap was one field in the bridge's state.

## Decision

**One renderer surface draws one window; the bridge fans out to many.**

- `state.sock` becomes `state.socks`: `%{socket => window_id | :all}`.
- A renderer names the window it draws in its `hello`
  (`{"t":"hello","renderer":"...","window":"main"}`). The bridge binds the
  socket to it, and later frames for that window go only to the renderers that
  asked for it.
- A renderer that announces no window is bound `:all` and receives every
  window's frames, filtering client-side. That is exactly what the backends did
  before they announced, so an older renderer keeps working.
- On connect, the bridge flushes every known window's latest frame. The
  renderer hasn't said what it draws yet, and it filters anyway — so late
  attachment still shows current state.
- A send failure prunes the socket: the peer is gone before its `:tcp_closed`
  arrived, and retrying a dead socket forever helps nobody.
- `Rext.Bridge.renderers/0` reports the attached windows, which is what
  `mix rext.run` needs to know when every window has a surface.

### Shutdown

`mix rext.run` used to halt the BEAM when *the* renderer exited. With several,
halting on the first exit would take every other window down with it — which
would make multi-window unusable in dev. `RextDev.Boot` now halts only when the
**last** renderer has detached.

## Consequences

- `mix rext.run` launches one renderer per declared window
  (`RextDev.Boot.window_ids/1`), not just the primary.
- Closing one window of a multi-window app leaves the others running.
- The `hello` frame gained an optional `window` field; all three backends now
  send it.
- Verified end-to-end against `rext_demo`: two renderers attach as
  `["main", "mirror"]`, both stay attached, and a click on the counter delivers
  a `window=main` frame to one and a `window=mirror` frame to the other.

**Still unverified: pixels.** This proves routing, not drawing. Nobody has seen
two rext windows on a screen at once, and per `PLAN.md`'s verification rule a
human sees the window before this counts as done-done. That pass is now worth
doing precisely because there is finally something multi-window to look at.

## Alternatives considered

**Broadcast everything, let every renderer filter.** Simplest possible change —
and it would have worked, since the backends already filter. Rejected as the
resting state because it sends every window's content to every renderer: waste
that grows with the product of windows and renderers, and it hands each
renderer state it has no business seeing. Kept as the *fallback* for renderers
that don't announce, where it costs nothing.

**One bridge (and port) per window.** Clean isolation, but it multiplies
listening sockets, makes port resolution N-dimensional, and gives the
in-process NIF host — where there is exactly one process and no socket at all —
nothing to mirror. The transport seam should look the same under both
transports.
