# rext Windows native renderer (WinForms)

The opt-in **native** backend for Windows — real Win32 controls and the platform
font (Segoe UI), the deliberate contrast to the Compose baseline (which draws
its own Skia widgets + bundled Inter for cross-platform consistency). It
implements the [rext render protocol](../../guides/render_protocol.md) over the
socket transport, the same wire format as the SwiftUI and Compose renderers.

"Basic" on purpose: WinForms builds with just the .NET SDK — no Windows App SDK,
no Visual Studio. A Fluent/WinUI 3 upgrade is a later option if the native feel
needs to be more modern.

## Build & run (on Windows)

```powershell
cd native\windows
$env:REXT_PORT=8137; $env:REXT_WINDOW="main"; dotnet run
```

- `REXT_PORT` — bridge port to connect to (default 8137).
- `REXT_WINDOW` — which window to draw (default `main`); frames for other windows
  are ignored.

Boot a rext BEAM to connect to first (from the `rext` repo; see its README).

## Notes

- **Windows-only** — WinForms can't build on macOS/Linux, so it's built and
  verified on Windows (and by the `windows-native` CI job on a `windows-latest`
  runner). Per `PLAN.md`, a human sees the window on a real display before CI is
  trusted.
- Targets `net8.0-windows` (LTS); bump the TFM in `RextRenderer.csproj` if your
  SDK is newer.
- Uses **Segoe UI** (native), not the bundled Inter — a native backend should
  look native, not identical to Compose.
