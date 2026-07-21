#!/usr/bin/env bash
# Build the in-process host: embeds the BEAM (stock OTP's libbeam.a) + the
# rect_nif render NIF into one native binary. Mirrors mob's iOS embedding, but
# on macOS the stock OTP already ships the static emulator lib, so no custom
# OTP build is needed — only OTP's vendored ryu + patched pcre2 (vendored here
# as prebuilt .a; rebuild from OTP source with the recipe in the ADR).
set -euo pipefail
cd "$(dirname "$0")"

# Toolchain roots (mise-managed on this machine).
ERL="${RECT_ERL_ROOT:-/Users/kevin/.local/share/mise/installs/erlang/29.0}"
EX="${RECT_ELIXIR_ROOT:-/Users/kevin/.local/share/mise/installs/elixir/1.20.0-otp-29}"
ERTS="$ERL/erts-17.0"
RECT_EBIN="${RECT_EBIN:-/Users/kevin/code/rect/_build/dev/lib/rect/ebin}"
HB="${HOMEBREW_LIB:-/opt/homebrew/lib}"

# 1. Render NIF as a shared object (enif_* resolved from the host at load time).
clang -shared -undefined dynamic_lookup -O2 \
  -I"$ERTS/include" \
  -o rect_nif.so rect_nif.c
echo "built: rect_nif.so"

# 2. Host object (paths injected so the binary is self-contained).
clang -c -O2 rect_host.c -o rect_host.o \
  -DRECT_ERL_ROOT="\"$ERL\"" \
  -DRECT_ERTS_BIN="\"$ERTS/bin\"" \
  -DRECT_BOOT="\"$ERL/bin/start_clean\"" \
  -DRECT_ELIXIR_EBIN="\"$EX/lib/elixir/ebin\"" \
  -DRECT_LOGGER_EBIN="\"$EX/lib/logger/ebin\"" \
  -DRECT_EBIN="\"$RECT_EBIN\"" \
  -DRECT_NIF_PATH="\"$(pwd)/rect_nif\""

# 3. Link the embedded VM. -rdynamic exports enif_* so the dlopen'd NIF resolves
#    them from the host. C++ link driver pulls in libc++ for the JIT (asmjit).
clang++ rect_host.o \
  "$ERTS/lib/libbeam.a" \
  "$ERTS/lib/internal/liberts_internal_r.a" \
  "$ERTS/lib/internal/libethread.a" \
  "$ERL/usr/lib/libei.a" \
  vendor/libepcre.a vendor/libryu.a \
  -L"$HB" -lzstd -lz -lm -lpthread -lncurses \
  -framework CoreFoundation -framework Carbon -framework Cocoa \
  -rdynamic \
  -o rect_host
echo "built: $(pwd)/rect_host"
echo "run:   ./rect_host    (boots embedded BEAM + rect app + NIF render path)"
