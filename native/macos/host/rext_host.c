// rext_host — in-process host for the embedded BEAM (macOS).
//
// This is the mob-faithful architecture: the native binary owns the process,
// boots an embedded ERTS (erl_start, linked from the stock OTP's libbeam.a),
// and the render backend is an in-process NIF (rext_nif) rather than a socket.
//
// This prototype host is headless: it boots the BEAM on the main thread and
// runs the rext app, whose windows render through the NIF (which logs frames).
// The GUI host adds NSApplication on the main thread + BEAM on a background
// thread + a rext_ui_render hook that updates SwiftUI — same boot recipe,
// documented in the ADR. Distribution stays on so an agent can drive it.
//
// Paths are injected by build.sh via -D so the binary is self-contained.

#include <stdio.h>
#include <stdlib.h>

void erl_start(int, char **);

#ifndef REXT_ERL_ROOT
#define REXT_ERL_ROOT "/opt/erlang"
#endif
#ifndef REXT_ERTS_BIN
#define REXT_ERTS_BIN REXT_ERL_ROOT "/erts/bin"
#endif
#ifndef REXT_BOOT
#define REXT_BOOT REXT_ERL_ROOT "/bin/start_clean"
#endif
#ifndef REXT_ELIXIR_EBIN
#define REXT_ELIXIR_EBIN "/opt/elixir/lib/elixir/ebin"
#endif
#ifndef REXT_LOGGER_EBIN
#define REXT_LOGGER_EBIN "/opt/elixir/lib/logger/ebin"
#endif
#ifndef REXT_EBIN
#define REXT_EBIN "/opt/rext/ebin"
#endif
#ifndef REXT_NIF_PATH
#define REXT_NIF_PATH "./rext_nif"
#endif

int main(void) {
    setenv("ROOTDIR", REXT_ERL_ROOT, 1);
    setenv("BINDIR", REXT_ERTS_BIN, 1);
    setenv("PROGNAME", "erl", 1);
    setenv("EMU", "beam", 1);
    setenv("HOME", "/tmp", 1);
    setenv("REXT_NIF_PATH", REXT_NIF_PATH, 1);

    const char *args[] = {"beam",
                          "--",
                          "-root",
                          REXT_ERL_ROOT,
                          "-bindir",
                          REXT_ERTS_BIN,
                          "-progname",
                          "erl",
                          "--",
                          "-boot",
                          REXT_BOOT,
                          "-pa",
                          REXT_ELIXIR_EBIN,
                          "-pa",
                          REXT_LOGGER_EBIN,
                          "-pa",
                          REXT_EBIN,
                          "-name",
                          "rext_host@127.0.0.1",
                          "-setcookie",
                          "rext_secret",
                          "-noshell",
                          "-noinput",
                          "-eval",
                          "'Elixir.Rext.Embedded':start().",
                          NULL};
    int ac = 0;
    while (args[ac])
        ac++;
    fprintf(stderr, "[rext_host] booting embedded BEAM (%d args)\n", ac);
    fflush(stderr);
    erl_start(ac, (char **)args);
    fprintf(stderr, "[rext_host] erl_start returned (unexpected)\n");
    return 0;
}
