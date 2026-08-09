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
| Windows  | Compose Desktop    | WinForms ✅ built (WinUI/Fluent a later upgrade) |
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
3. ✅ **Native backends per platform** — SwiftUI (built; window verified on macOS)
   and WinForms (`native/windows`, built + CI-compiling on windows-latest).
   **Windows visual pass done**: `dotnet run` renders real Win32 controls
   (native title bar, Segoe UI, system buttons) against a live BEAM over the
   socket bridge, and `Rext.Test.click/2` over dist drove a live update
   ("Count: 0" → "Count: 1") reflected in the native window. A Fluent/WinUI 3
   upgrade for Windows is a later option if the native feel needs to be more
   modern.
4. **Per-platform agent visual verification** — the harness upgrade above (the
   investment that removes the human from the pixel-checking loop).
5. ~~**rext_mcp**~~ — **not pursued.** Agents drive rext via `mix rext.connect` +
   `Rext.Test` over dist (same as mob in practice). An MCP server would only add
   value for a non-shell MCP client (Claude Desktop/Cursor/etc.); revisit if that
   need appears. See `decisions/2026-07-22-skip-rext-mcp.md`.
6. **In-process NIF host, production** — finish the embedded-BEAM host beyond the
   headless proof. ✅ **Windows headless proof done too**
   (`native/windows/host`, `decisions/2026-08-07-in-process-nif-host-windows.md`):
   `erl_start` ported cleanly from macOS's recipe — dynamically resolved from
   `beam.smp.dll` (no custom OTP build needed, and *less* linking than macOS
   since the DLL is fully self-contained), `rext_nif.c` builds for Windows
   **unchanged** (erl_nif.h's function-pointer NIF ABI needs no host-export
   trick the way Unix's flat symbol table does). One Windows-only gotcha with
   no Unix analogue: `sys_primitive_init(beam_handle)` must run before
   `erl_start` or boot crashes (`No ERLANG_DICT resource`) — Windows stores
   preloaded modules as a PE resource, and needs the DLL told its own handle
   before it can find its own resource section. Verified headless, same as
   where macOS started: NIF receives render frames, events flow back via
   `enif_send`, driven over dist with `Rext.Test`. GUI wiring (a real WinForms
   window, not just logged frames) is the remaining piece — same open
   state as macOS's own GUI host.
7. **Distribution: cold install + hot update** — ✅ **cold path built**
   (`mix rext.release` + `mix rext.installer` in `rext_dev`; verified
   end-to-end on Windows, including a silent install/uninstall-while-running,
   against `rext_demo`). Hot path still scoped-not-built; see below.
8. **Component surface** — the desktop vocabulary itself. rext renders five
   node types; `guides/desktop_surface_matrix.md` is the honest inventory and
   the source the `bd` backlog is generated from.

## Distribution — cold install + hot update (scoped 2026-08-07)

Shipping an app to end users splits into two tiers that don't share a mechanism:

- **Cold path** (new install, or any update touching native code — the
  renderer, the NIF, an ERTS bump): a conventional installer. **Inno Setup**
  is the pick — a plain-text `.iss` script compiled via a CLI (`ISCC.exe`), no
  GUI step, matching the "basic on purpose" ethos `native/windows/README.md`
  already states for WinForms itself. Payload is whatever `mix rext.release`
  already produces (release + renderer + launcher); the installer's uninstall
  step needs to run the release's `stop` command first, or it can orphan a
  running `erl.exe`. WiX/MSI is the fallback if Group Policy / enterprise
  deployment ever becomes a real requirement — not needed now. **Built**
  (`mix rext.installer`), with one known limitation: the launcher pins a fixed
  bridge port, so only one instance runs at a time (`bd` issue `rext-3hi`).
- **Hot path** (pure BEAM code changes, no restart): OTP's own release-handling
  machinery — `.appup` → `systools:make_relup` → an upgrade tarball → the
  running node's `release_handler` (unpack → dry-run check → install → make
  permanent). `mix release` already produces the upgrade tarball once an
  appup exists for a version bump; none of this needs custom infrastructure
  to *work*, only to be *driven*: a small OTA module (ships in the app, not
  `rext_dev` — this runs in production) that checks a version manifest,
  downloads and **signature-verifies** the tarball (this is code executing
  inside a live VM — an unverified download here is arbitrary code execution,
  not just a corrupted file), applies it, and health-checks before making it
  permanent so a bad upgrade reverts on next cold start instead of sticking.
  Not yet built.

**Explicit non-goal: rext facilitates the hot-update *mechanism*, not appup
*authoring*.** Writing (or generating) correct `.appup` files for a given
app's stateful code changes, and standing up the manifest/tarball server that
hosts them, is the app author's problem to solve on their own infrastructure —
same way `rext` doesn't tell you where your `Rext.Window` state comes from.
The trivial case (a changed module with no stateful shape change — most
`Rext.Window` callback edits) is mechanical enough that a generator diffing
compiled `.beam` files between two versions could cover it later, but that's
an optional convenience on top, not a blocker: the underlying pipeline
(`appup` → `relup` → tarball → `release_handler`) is standard, well-proven OTP
machinery, independent of who or what authors the appup.

**What stays out of the hot path, permanently, not just "for now":** anything
that's an OS-level file the process has open — the renderer `.exe`, the NIF
`.dll`, ERTS itself. Windows won't let you overwrite a loaded DLL out from
under a running process the way Unix will; those changes need the cold path.

## Parallel-hardware / multi-agent model

Compose is write-once/JVM, so build here (runs on macOS too → first visual check
here), then clone on the Linux/Windows machines for the arch-matched look. Parallel
Claude instances on those boxes are **verifiers** (clone, `./gradlew run`, connect
to a BEAM, eyeball, report), not primary authors — which is what the protocol spec
enables.
