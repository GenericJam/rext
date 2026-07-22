# rext — Agent Instructions

**rext is mob's desktop sibling.** If you know mob, you know rext: same
programming model (a unit of UI is a supervised GenServer that produces a
component tree; the tree is serialized and drawn by a native backend; events
come back over the same channel), re-committed to *desktop* paradigm and
concerns. rext was seeded by copying mob's platform-agnostic core, not by
sharing a library — a common `beam_native_ui` package is a later refactor only
if duplication proves significant and enduring.

Read this file before touching anything. It carries the knowledge that is
expensive to rediscover.

---

## What rext is, in one paragraph

You write Elixir. A `Rext.Window` is one supervised GenServer whose state is a
`Rext.Socket`; its `render/1` returns a component tree. `Rext.Renderer`
normalizes that tree to a JSON frame, and a render backend draws it. Events
(clicks, input) come back and route to the window's `handle_event/3`. The window
state and render tree are authoritative **on the BEAM** — the backend only
draws — so you connect over Erlang distribution to inspect and drive a running
app (`Rext.Test`), and hot-reload code without a restart. Desktop paradigm: the
unit is a *window*, apps run *many* at once (many processes), and there is no
mobile navigation stack — "another view" is "another window", i.e. another
process.

## Repo topology

| Repo | Role |
|------|------|
| `rext` (this repo) | Runtime library, ships in the app. |
| `rext_dev` | Dev + agent tooling: `mix rext.run`, `mix rext.connect`. Never a shipped dependency. |
| `rext_new` | Project generator: `mix rext.new my_app`. |
| `rext_demo` | Proof-of-concept app (sibling; multi-window). |

## Toolchain — READ THIS FIRST (cross-user env)

This machine runs agents as user `claude` while `~/code` is owned by `kevin`.
**`elixir`/`erl`/`mix` are NOT on the `claude` account's non-interactive PATH.**
Use the mise install paths directly:

```bash
export PATH="/Users/kevin/.local/share/mise/installs/erlang/29.0/bin:/Users/kevin/.local/share/mise/installs/elixir/1.20.0-otp-29/bin:$PATH"
```

Prepend that in every shell invocation that runs mix/elixir/erl. Toolchain:
Elixir 1.20 / OTP 29 (erts-17.0). `.tool-versions` pins it.

## The transport architecture (the core design)

`Rext.Transport` is the one seam between a window and its render backend. Two
implementations, selected by `config :rext, :transport, …`; everything above the
seam (Window, Renderer, Socket, Test) is identical across both:

- **`Rext.NifBridge`** — *in-process*, the **mob-faithful** path. A native host
  binary owns `main()`, embeds the BEAM as a guest thread, and bridges via the
  `rext_nif` NIF (render is a direct call; events return via `enif_send`). This
  is the production target.
- **`Rext.Bridge`** — *out-of-process*, a renderer connected over a localhost
  socket (`{:packet, 4}` JSON frames). The "Port partner" model; also the path
  to a browser/remote renderer. Fastest to iterate; used for the socket demo.

Render path is a **cast** (never a call) to the transport, to avoid the
transport-handler reentrancy trap (see mob's notes): the window calls the
transport, and a socket/NIF event can call back into the window without
deadlock.

## The in-process host recipe (do not rediscover this)

The full story is in `decisions/2026-07-20-in-process-nif-host.md`. The essentials:

- **macOS ships the static emulator lib.** `$OTP/erts-17.0/lib/libbeam.a`
  exports `erl_start` — the exact thing mob had to cross-build for iOS is
  already there. No custom OTP build.
- **Only two components need compiling from OTP source**: OTP's vendored **ryu**
  (`d2s.c`) and its **patched pcre2** (`-DERLANG_INTEGRATION`, plus three
  generated headers from `pcre.mk`). System/homebrew pcre2 does NOT work — it
  lacks OTP's `pcre2_set_loops_left_8` etc. Prebuilt copies are vendored in
  `native/macos/host/vendor/`.
- **Link** with `clang++` (the JIT is C++): `libbeam.a
  liberts_internal_r.a libethread.a libei.a libepcre.a libryu.a -lzstd -lz -lm
  -lpthread -lncurses -framework CoreFoundation -framework Carbon -framework
  Cocoa -rdynamic`. `-rdynamic` exports `enif_*` so the dlopen'd NIF resolves
  them from the host.
- **Boot** needs env (`ROOTDIR`, `BINDIR`, `PROGNAME=erl`, `EMU=beam`, `HOME`)
  and an erl arg vector: `-root/-bindir`, `-boot start_clean`, `-pa` for elixir
  + logger + rext ebin, `-name/-setcookie` (dist), `-eval
  Rext.Embedded.start()`.
- **Proven end-to-end**: ERTS + Elixir + rext all boot in-process; the NIF
  receives render frames; events flow back via `enif_send`.
- **GUI-session caveat**: a window will NOT display when the process is launched
  from a shell detached from the Aqua login session (`screencapture` →
  "could not create image from display"; `open` → OSLaunchd Code=125). The data
  path is verifiable headlessly regardless; on-screen pixels need the user's GUI
  session. **Don't chase this as a bug — it's an environment boundary.**

## Day-to-day dev loop

```bash
# runtime lib
mix test
mix compile --warnings-as-errors

# socket renderer (fast iteration, agent-verifiable)
(cd native/macos && ./build.sh)          # builds RextRenderer.app
elixir --name rext_demo@127.0.0.1 --cookie rext_secret -S mix run --no-halt dev/demo.exs

# in-process NIF host (mob-faithful)
(cd native/macos/host && ./build.sh)     # builds rext_host (embeds the BEAM)
./native/macos/host/rext_host            # boots BEAM + rext + NIF in one process
```

Then drive over dist from a second node (this is the agent workflow):

```elixir
node = :"rext_demo@127.0.0.1"   # or :"rext_host@127.0.0.1"
Node.connect(node)
Rext.Test.window(node)          # window module
Rext.Test.assigns(node)         # live assigns
Rext.Test.tree(node)            # render tree
Rext.Test.click(node, :inc)     # drive a control by its on_click tag
```

Window/tree state is authoritative on the BEAM, so `Rext.Test` works with or
without a renderer attached. Prefer it over screenshots — it's exact and fast.

## Quality gates — the pre-commit checklist

Run all, in order, before committing (matches CI and the `.githooks/pre-push`
gate; activate the hook once per clone with `mix setup` or `git config
core.hooksPath .githooks`):

```bash
mix test
mix format                 # apply Elixir formatting
mix credo --strict         # includes ExSlop (AI-pattern checks) + jump_credo_checks
mix erlfmt --check src/    # Erlang NIF stub formatting
xcrun clang-format --dry-run -Werror native/macos/host/*.c
swiftlint native/macos     # brew install swiftlint
```

`mix deps.audit` (CVE scan) runs in the release preflight; it needs
`mix do app.start + deps.audit` (mix_audit doesn't `ensure_all_started`
yaml_elixir on its own).

Native changes (Swift/C) aren't exercised by Elixir tests — build and drive the
renderer/host and verify via `Rext.Test` before committing.

## Don't write this slop

`mix credo --strict` (via `ex_slop`) refuses these; don't write them in the
first place:

- **Error handling**: no blanket `rescue _ -> nil`; no `try/rescue` around
  functions that don't raise. Rescue the specific exception or let it crash.
- **Enum idioms**: `Enum.reject(&is_nil/1)` not `filter(&(&1 != nil))`;
  `Enum.empty?` not `length(x) == 0`; `Map.new/2` not `reduce(%{}, …Map.put)`;
  `Enum.map_join` not `map |> join`.
- **Maps**: one key type per map; iterate directly, don't `Map.keys |> map`.
- **`with`**: no identity `else err -> err`.
- **Docs/comments**: no "This module provides functionality for…" moduledoc; no
  obvious/narrator/step comments (`# Fetch the user`, `# We need to…`, `# Step
  1`); no `## Parameters/## Returns` boilerplate. State *why* or what's
  surprising, else omit.
- **Shape**: don't shadow `Kernel` names (`length`, `node`, `min`); don't rebind
  a parameter; don't `x = foo(); x`.

## Testing discipline

Every behavior gets a test — including build/CLI helpers (the `mix erlfmt` task,
`rext_new`'s generator, etc.), not just runtime modules. A bug found by a test
costs minutes; one found by a user costs a report-to-fix cycle. When you touch
something untested, add coverage or note the follow-up.

## Key files

- `lib/rext/window.ex` — GenServer wrapper, lifecycle, transport dispatch.
- `lib/rext/socket.ex` — assigns + window metadata.
- `lib/rext/renderer.ex` — tree → normalized JSON frame; token resolution.
- `lib/rext/transport.ex` — the backend seam (behaviour).
- `lib/rext/bridge.ex` — socket transport (out-of-process).
- `lib/rext/nif_bridge.ex` — NIF transport (in-process).
- `lib/rext/test.ex` — agent harness (RPC introspection + drive).
- `lib/rext/embedded.ex` — boot entry for the in-process host.
- `src/rext_nif.erl` — NIF stub.
- `native/macos/main.swift` — socket SwiftUI renderer.
- `native/macos/host/` — in-process host (`rext_nif.c`, `rext_host.c`, `build.sh`).

## Decision log

Non-obvious decisions go in `decisions/YYYY-MM-DD-slug.md` (lightweight ADRs,
one per decision, append-only; supersede rather than edit). Start there for the
"why" behind the architecture:

- `2026-07-20-rext-prototype-architecture.md` — the overall shape.
- `2026-07-20-in-process-nif-host.md` — the in-process embedding recipe.

## Keep this file up to date

When you change a convention, add CLI surface, or hit a new gotcha, fix it here
in the same commit. Out-of-date guidance causes wrong decisions everywhere
downstream. `ex_slop` gains AI-pattern checks regularly — skim its changelog
periodically and refresh the slop list above.
