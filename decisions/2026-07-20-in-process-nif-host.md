# In-process NIF host on macOS (mob-faithful architecture)

- Date: 2026-07-20
- Status: accepted
- Supersedes the "socket is required on macOS" framing in
  `2026-07-20-rect-prototype-architecture.md` (§"Why the socket transport").

## Context

The first prototype used an out-of-process socket renderer and I described it as
a macOS constraint. That was wrong: iOS and macOS have the *same* main-thread
and NIF rules. mob's architecture — native app owns `main()`, embeds the BEAM
as a guest thread, bridges via an in-process NIF — works identically on macOS.
The socket was a launch-model choice (BEAM-hosted-by-mix), not a platform limit.
This decision records the in-process host, now built and verified.

## What was proven (with running evidence)

1. **ERTS embeds in-process from the stock OTP install.** `erl_start` is exported
   by `$OTP/erts-17.0/lib/libbeam.a` — the very thing mob had to cross-build for
   iOS is shipped on macOS. A C++ host linking it booted the VM in-process
   (`IN-PROCESS BEAM OK otp=29`).
2. **Elixir + rect run embedded.** Same host, booting Elixir, ran
   `Rect.Renderer.frame/2` and returned the JSON frame.
3. **Full host works.** `native/macos/host/rect_host` boots the embedded BEAM,
   starts the rect app with the NIF transport, opens the counter window; the NIF
   receives render frames in-process (logged `Count: 1/2/3`), the window
   registers its pid, and UI events flow back via `enif_send`
   (`simulate_ui_event` → `{:rect_ui_event, …}` → `handle_event`). Driven over
   dist with `Rect.Test`.

## The link recipe (macOS, OTP 29 / erts-17.0)

Stock OTP resolves everything except two components OTP compiles straight into
the non-relinkable `beam.smp`: its vendored **ryu** (float formatting,
`d2s_buffered_n`) and its **patched pcre2** (regex with reduction-counting hooks
like `pcre2_set_loops_left_8`). Build those from OTP source:

- ryu: compile `erts/emulator/ryu/d2s.c` → `libryu.a`.
- pcre2: generate 3 headers from `pcre2_match.c` (the grep/awk snippets in
  `pcre/pcre.mk`), then compile the `pcre2_*.c` list with `-DERLANG_INTEGRATION
  -I.` → `libepcre.a`. (Prebuilt copies are vendored in `host/vendor/`.)

Link (see `host/build.sh`):

    clang++ rect_host.o \
      $ERTS/lib/libbeam.a $ERTS/lib/internal/liberts_internal_r.a \
      $ERTS/lib/internal/libethread.a $OTP/usr/lib/libei.a \
      vendor/libepcre.a vendor/libryu.a \
      -L/opt/homebrew/lib -lzstd -lz -lm -lpthread -lncurses \
      -framework CoreFoundation -framework Carbon -framework Cocoa -rdynamic

Boot needs env (`ROOTDIR`, `BINDIR`, `PROGNAME=erl`, `EMU=beam`, `HOME`) and an
erl arg vector with `-root/-bindir`, `-boot start_clean`, `-pa` for elixir +
logger + rect ebin, `-name/-setcookie` for dist, `-eval Rect.Embedded.start()`.
`-rdynamic` exports `enif_*` so the dlopen'd NIF resolves them from the host.

## Transport seam

`Rect.Transport` behaviour with two impls: `Rect.NifBridge` (in-process, this
host) and `Rect.Bridge` (socket, out-of-process). Window/Renderer/Socket/Test
are identical across both. Selected by `config :rect, :transport, …`.

## Consequences / follow-ups

- **NIF is dynamic** (`.so` + `-rdynamic`), simpler than mob's iOS static-NIF
  driver-table approach — viable because macOS allows app-loaded dylibs.
- **GUI host** is the remaining piece: NSApplication on the main thread, BEAM on
  a background thread, and a `rect_ui_render` hook (weak symbol the host
  provides) that hands the JSON frame to the SwiftUI view from `native/macos`.
  The current host is headless (BEAM on main thread) and verified without a
  window; the on-screen render can't be verified from a shell detached from the
  Aqua session regardless.
- **Vendored ryu/pcre .a** are convenience artifacts; a real build should
  compile them from a pinned OTP source checkout matching the target ERTS.
- **Single-window** NIF (one stored pid); generalize to a pid-per-window map.
