# rext Compose Desktop renderer

The **universal baseline backend** — one Kotlin/Compose (Skia) codebase that runs
on macOS, Windows, and Linux with consistent styling. It implements the
[rext render protocol](../../guides/render_protocol.md) over the socket
transport, the same wire format as the SwiftUI renderer.

## Build & run

Uses the Gradle wrapper (no system Gradle needed):

```bash
./gradlew build                       # compile
REXT_PORT=8137 REXT_WINDOW=main ./gradlew run   # launch, connect to a running rext BEAM
```

- `REXT_PORT` — the bridge port to connect to (default 8137).
- `REXT_WINDOW` — which window this renderer draws (default `main`); frames for
  other windows are ignored.

Boot a BEAM to connect to (from the `rext` repo): see its README / `dev/demo.exs`.

## Status

- Compiles (Kotlin 2.4 + Compose Multiplatform 1.8.2, Gradle 9.6 / JDK 17).
- Verified to connect to the BEAM and complete the protocol handshake
  (`renderer hello: "compose-desktop"`).
- **Window display requires a real GUI session** — running headless raises
  `java.awt.HeadlessException`, exactly like the SwiftUI renderer. Per
  `PLAN.md`, a human sees the window on a real, arch-matched display before CI
  is trusted.

## Fonts

Text uses **Inter** (OFL), bundled at `src/main/resources/font/Inter.ttf` and
applied in `Main.kt`, so it renders consistently across macOS/Windows/Linux
instead of depending on each OS's system fonts — the biggest "looks different
per platform" variable, removed. License: `src/main/resources/font/OFL.txt`.

## TODO

- Components track the protocol catalog (`column`/`row`/`text`/`button`);
  add new node types here as the protocol grows (e.g. `text_field`).
