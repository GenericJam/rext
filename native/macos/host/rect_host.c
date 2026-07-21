// rect_host — in-process host for the embedded BEAM (macOS).
//
// This is the mob-faithful architecture: the native binary owns the process,
// boots an embedded ERTS (erl_start, linked from the stock OTP's libbeam.a),
// and the render backend is an in-process NIF (rect_nif) rather than a socket.
//
// This prototype host is headless: it boots the BEAM on the main thread and
// runs the rect app, whose windows render through the NIF (which logs frames).
// The GUI host adds NSApplication on the main thread + BEAM on a background
// thread + a rect_ui_render hook that updates SwiftUI — same boot recipe,
// documented in the ADR. Distribution stays on so an agent can drive it.
//
// Paths are injected by build.sh via -D so the binary is self-contained.

#include <stdio.h>
#include <stdlib.h>

void erl_start(int, char **);

#ifndef RECT_ERL_ROOT
#define RECT_ERL_ROOT "/opt/erlang"
#endif
#ifndef RECT_ERTS_BIN
#define RECT_ERTS_BIN RECT_ERL_ROOT "/erts/bin"
#endif
#ifndef RECT_BOOT
#define RECT_BOOT RECT_ERL_ROOT "/bin/start_clean"
#endif
#ifndef RECT_ELIXIR_EBIN
#define RECT_ELIXIR_EBIN "/opt/elixir/lib/elixir/ebin"
#endif
#ifndef RECT_LOGGER_EBIN
#define RECT_LOGGER_EBIN "/opt/elixir/lib/logger/ebin"
#endif
#ifndef RECT_EBIN
#define RECT_EBIN "/opt/rect/ebin"
#endif
#ifndef RECT_NIF_PATH
#define RECT_NIF_PATH "./rect_nif"
#endif

int main(void) {
    setenv("ROOTDIR", RECT_ERL_ROOT, 1);
    setenv("BINDIR", RECT_ERTS_BIN, 1);
    setenv("PROGNAME", "erl", 1);
    setenv("EMU", "beam", 1);
    setenv("HOME", "/tmp", 1);
    setenv("RECT_NIF_PATH", RECT_NIF_PATH, 1);

    const char *args[] = {"beam",
                          "--",
                          "-root",
                          RECT_ERL_ROOT,
                          "-bindir",
                          RECT_ERTS_BIN,
                          "-progname",
                          "erl",
                          "--",
                          "-boot",
                          RECT_BOOT,
                          "-pa",
                          RECT_ELIXIR_EBIN,
                          "-pa",
                          RECT_LOGGER_EBIN,
                          "-pa",
                          RECT_EBIN,
                          "-name",
                          "rect_host@127.0.0.1",
                          "-setcookie",
                          "rect_secret",
                          "-noshell",
                          "-noinput",
                          "-eval",
                          "'Elixir.Rect.Embedded':start().",
                          NULL};
    int ac = 0;
    while (args[ac])
        ac++;
    fprintf(stderr, "[rect_host] booting embedded BEAM (%d args)\n", ac);
    fflush(stderr);
    erl_start(ac, (char **)args);
    fprintf(stderr, "[rect_host] erl_start returned (unexpected)\n");
    return 0;
}
