# rext — Plan

> Living planning doc. The "why" and the roadmap; durable per-decision rationale
> goes in `decisions/`, and agent conventions in `CLAUDE.md`. Keep this current.

## The thesis

rext's value is the intersection of three things — and the third is what makes
the first two worth the trouble:

1. **Native feel** — real per-platform UI, not a lowest-common-denominator webview.
2. **BEAM** — a unit of UI is a supervised GenServer; OTP supervision, hot code
   reload, and distribution come for free.
3. **Agentic coding** — the framework is built to be driven and verified by AI
   agents (the `Rext.Test` harness, the render protocol, the pluggable backends).

"Native feel + BEAM" alone, aimed at Elixir developers, is niche. The multiplier
is agentic coding: *native-on-every-platform* is normally a human-labor problem
(N toolkits, N sets of quirks drifting apart — exactly mob's pain). Agents absorb
that per-backend labor, so "native feel, everywhere, in Elixir" becomes tractable
where it wouldn't be by hand. **rext is the easiest way to build a native-feel
desktop app _with an agent_.**

## Backend strategy — five backends

Every platform gets a **consistent baseline (Compose)**; macOS and Windows
additionally get a **native premium backend**. Linux is Compose-only (no single
"native Linux" worth a dedicated backend).

| Platform | Baseline (default) | Native (opt-in) |
|----------|--------------------|-----------------|
| macOS    | Compose Desktop    | SwiftUI ✅ built |
| Windows  | Compose Desktop    | WinUI (future)  |
| Linux    | Compose Desktop    | — |

So five backend targets: `{Compose-mac, Compose-win, Compose-linux, SwiftUI-mac,
WinUI-win}`. Compose is **one Kotlin codebase** run on three OSes (Skia/Skiko →
identical rendering, which is exactly the consistency mob struggles to maintain
across SwiftUI+Compose). The native backends are a *feel* upgrade, not the reason
rext exists.

**Why both, and why this beats mob's position:** mob is forced native on mobile
and pays the consistency cost. rext doesn't have to — the pluggable transport lets
it ship *consistency-by-default* (Compose everywhere) **and** *native-when-you-want-it*
(SwiftUI today, WinUI later). That serves both "same look, my brand, everywhere"
and "feels native on my OS" from one framework.

## What makes it possible (already built)

- **Transport-agnostic render protocol** — a backend is anything that speaks it.
  See `guides/render_protocol.md`. Two transports exist: `Rext.Bridge`
  (out-of-process socket) and `Rext.NifBridge` (in-process, embedded BEAM).
- **`Rext.Window` / `Rext.Socket` / `Rext.Renderer`** — the BEAM-side model,
  platform-agnostic.
- **`Rext.Test`** — the agent harness (RPC introspect + drive over dist).
- **Reference native backend** — SwiftUI on macOS (socket) + the in-process NIF
  host that embeds the stock OTP BEAM (`native/macos`). Proves the native path
  and the pluggable architecture.
- **Quality gates + 4 repos** (`rext`, `rext_dev`, `rext_new`, `rext_demo`) on
  GitHub; 37 tests; credo/ExSlop/format/erlfmt/CI.

## The verification frontier (the key investment)

This is the honest bottleneck. An agent can *write and build* a backend, but a
GUI's correctness can't be confirmed by a green build — this project has twice
proven that a fully-green renderer still crashes at runtime (root, then the
WindowServer/session issue). And an agent can't see a window.

So today the loop is: **agent writes + builds + logically verifies; a human does
the final visual look on a real, arch-matched display.** Rules that fall out of this:

- **Visual verification precedes CI.** CI is the regression net *behind* a human
  sign-off, never the first proof a GUI works.
- **Verify on an arch-matched target.** A VM only counts if its OS/arch match what
  ships (Apple-Silicon VMs are ARM; a `linux-x64` artifact needs x64 or Rosetta).

The investment that scales the five-backend vision is **per-platform, agent-accessible
visual verification** — screenshot-over-dist, an accessibility-tree walk, synthetic
event injection (mob's "cocoon" ambition). That turns "agent writes a backend" into
"agent builds *and verifies* a backend" with the human increasingly out of the
pixel-checking loop. Until it exists, a human sees the window.

## Compose consistency — what to rely on

Compose Desktop draws with Skia, so layout/widgets are consistent across
platforms — validating layout/logic on the Mac transfers. But "compiles on Linux"
≠ "works on Linux": the runtime risks (Skiko native-lib load, GL context init,
fonts) are exactly what a compile can't catch. So Linux/Windows still need a
launch-and-eyeball smoke test — cheaper than re-verification, not skippable.
Mitigation: **bundle a font** with the renderer so text doesn't vary by OS.

## Roadmap

1. ✅ **Protocol spec** — `guides/render_protocol.md` (the contract all five bind to).
2. ✅ **Compose Desktop renderer** — `native/compose`, Kotlin + Compose MP, Inter
   bundled. CI-green building on Linux/Windows/macOS. **Visually verified on a real
   display: macOS ✅ and Linux ✅** (Linux being the whole point — it's Compose-only
   there). The "validate on macOS → transfers to Linux" thesis held; the bundled
   font kept text consistent. Windows visual pass still pending (needs a Windows box).
3. **Native backends per platform** — SwiftUI (built, reference; window verified on
   macOS); WinUI when there's a Windows env to build/verify in. ← next native work
4. **Per-platform agent visual verification** — the harness upgrade above (the
   investment that removes the human from the pixel-checking loop).
5. **rext_mcp** — MCP server fronting `Rext.Test` so agents get typed tools.
6. **In-process NIF host, production** — finish the embedded-BEAM host beyond the
   headless proof (macOS first).

## Parallel-hardware / multi-agent model

Compose is write-once/JVM, so build here (runs on macOS too → first visual check
here), then clone on the Linux/Windows machines for the arch-matched look. Parallel
Claude instances on those boxes are **verifiers** (clone, `./gradlew run`, connect
to a BEAM, eyeball, report), not primary authors — which is what the protocol spec
enables.
