# In-process NIF host on Windows

- Date: 2026-08-07
- Status: accepted
- Sibling to `2026-07-20-in-process-nif-host.md` (macOS). Same architecture,
  ported; this doc records what's genuinely different on Windows.

## Context

`PLAN.md` scoped the in-process NIF host as "macOS first" because embedding
ERTS in a host process was unproven anywhere but macOS, and Windows has no
public precedent for it the way macOS's mob-derived recipe does. This decision
records that it ports cleanly — with one Windows-specific wrinkle that has no
Unix equivalent at all (`sys_primitive_init`, below) — and turned out to need
*less* linking than macOS, not more.

## What was proven (with running evidence)

1. **`erl_start` is exported from the stock OTP Windows install**, dynamically:
   `erts-17.0.5/bin/beam.smp.dll` exports it directly (confirmed by parsing its
   PE export table). No custom OTP build, no vendoring — same headline result
   as macOS's `libbeam.a` finding, reached a different way (`LoadLibrary` +
   `GetProcAddress` instead of static linking, since no import `.lib` for it
   ships).
2. **`beam.smp.dll` is fully self-contained.** Its PE export table already
   includes the patched `pcre2_*_8` functions (statically compiled in) and its
   import table is only standard system DLLs (`kernel32`, `advapi32`, `user32`,
   `ws2_32`, `iphlpapi`, the VC++ runtime). Unlike macOS, there's no equivalent
   of separately linking `liberts_internal_r.a`/`libethread.a`/vendored
   pcre2+ryu — one dynamically-loaded DLL is the whole emulator.
3. **The NIF ABI needs no host-side export trick.** macOS's `rext_nif.so` binds
   `enif_*` via `-undefined dynamic_lookup` against symbols the host exports
   with `-rdynamic` — a Unix flat-symbol-table technique with no Windows
   equivalent. Windows NIFs don't need one: `erl_nif.h`'s `ERL_NIF_INIT` macro
   expands, on Windows, to a `WinDynNifCallbacks` function-pointer struct that
   the emulator populates when it loads the NIF DLL (passed to the exported
   `nif_init` entry point). Every `enif_*` call is a struct member call, not a
   linked symbol. Practical result: `native/macos/host/rext_nif.c` ports to
   Windows **unchanged** but for the removed GUI weak-symbol hook (next section)
   — same source builds as a DLL instead of a `.so`, no special linker flags.
4. **Full host works, headless, exactly matching the macOS host's proven
   scope.** `native/windows/host/rext_host.exe` boots the embedded BEAM, starts
   the rext app with the NIF transport, opens the counter window; the NIF
   receives render frames in-process, the window registers its pid, and UI
   events flow back via `enif_send` (`simulate_ui_event` →
   `{:rext_ui_event, …}` → `handle_event` → re-render). Driven over dist with
   `Rext.Test`, including the reverse path called directly
   (`:rpc.call(node, :rext_nif, :simulate_ui_event, [...])`).

## The one Windows-specific gotcha: `sys_primitive_init`

Calling `erl_start` alone crashes at boot: `No ERLANG_DICT resource`. Windows
OTP stores the preloaded core modules (the ones Unix links in as a static C
array) as a PE resource named `ERLANG_DICT`, embedded in `beam.smp.dll` itself.
`FindResource` needs the *module handle* of whichever binary holds the
resource — but called with `NULL` (which erts' internal code does unless told
otherwise) it resolves against the calling process's own main executable
(`rext_host.exe`), which obviously doesn't have it.

The fix, read from OTP's own source
(`erts/emulator/sys/win32/sys.c`, `beam_module` global +
`sys_primitive_init(HMODULE)`): call the also-exported `sys_primitive_init`,
passing it the `HMODULE` `LoadLibrary` returned for `beam.smp.dll`, **before**
calling `erl_start`. That sets the DLL's internal `beam_module` handle so its
own `FindResource(beam_module, ...)` calls resolve against itself. This is
exactly what `erl.exe`'s own launch path does implicitly (it goes through
`erlexec.dll`, which receives its own module handle) — a host bypassing that
launcher has to replicate it explicitly. No Unix analogue: Unix has no
resource-section concept, so this entire class of bug can't occur there.

## The recipe (Windows, OTP 29 / erts-17.0.5)

No custom OTP build, no vendored artifacts — beam.smp.dll already has
everything (see point 2 above). Toolchain: MinGW-w64 (`choco install mingw`);
MSVC was never needed since nothing here is statically linked against an
erts-provided `.lib`.

```
gcc -shared -O2 -I"$ErtsBin/../include" -o rext_nif.dll rext_nif.c
gcc -O2 rext_host.c -o rext_host.exe
```

(see `native/windows/host/build.ps1` — paths come from a generated
`rext_paths.h`, not command-line `-D` defines: PowerShell's native-argv
marshaling mangles embedded quotes needed to turn a path into a C string
literal, so writing the macros straight to a file sidesteps shell quoting
entirely.)

Boot sequence in `rext_host.c`'s `main`:

1. `_putenv_s` for `ROOTDIR`, `BINDIR`, `PROGNAME=erl`, `EMU=beam`,
   `REXT_NIF_PATH` (no `HOME` — Windows has no such convention and erts didn't
   need it here, unlike macOS).
2. `LoadLibraryA("beam.smp.dll")`.
3. `GetProcAddress` for `sys_primitive_init` and `erl_start`.
4. Call `sys_primitive_init(beam_handle)` — **before** `erl_start`, or it
   crashes (see above).
5. Call `erl_start(argc, argv)` with the same shape of erl arg vector as
   macOS: `-root`/`-bindir`, `-boot start_clean`, `-pa` for elixir + logger +
   rext ebin, `-name`/`-setcookie`, `-eval 'Elixir.Rext.Embedded':start().`.

## Transport seam

Same as macOS — no changes needed. `Rext.Transport` behaviour, two impls
(`Rext.NifBridge`, `Rext.Bridge`), selected by `config :rext, :transport, …`.
`Rext.Embedded` (the `-eval` target) is already fully platform-agnostic Elixir;
reused as-is.

## Consequences / follow-ups

- **GUI host is the remaining piece, same as macOS's own state.** The render
  NIF is headless (logs frames); wiring it to a real WinForms window needs a
  different mechanism than macOS's weak-symbol hook, because Windows DLLs
  can't call an unresolved symbol against whatever loaded them the way a
  dlopen'd Unix `.so` can. The likely shape: the NIF DLL posts to a window
  handle (`PostMessage`/named pipe/shared queue) rather than calling into the
  host directly — not yet built or designed in detail.
- **Single-window NIF** (one stored pid), same simplification as macOS;
  generalize to a pid-per-window map when multi-window matters.
- **Verified headless only** — per `PLAN.md`'s verification-frontier rules, a
  real on-screen window still needs a human to look at it once the GUI host
  exists; this proof is the data-path half, same as where macOS started.
