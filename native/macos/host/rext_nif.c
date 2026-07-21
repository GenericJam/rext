// rext_nif — in-process render backend NIF (macOS host).
//
// Loaded by the embedded BEAM. Bridges the render tree from Elixir to the
// native UI and delivers UI events back to the owning window process via
// enif_send. This is the in-process counterpart of the socket transport in
// Rext.Bridge — same protocol (JSON frames + event tags), no wire.
//
// For the prototype, render() logs frames (headless-verifiable) and calls the
// weak `rext_ui_render` hook if the host provides one (GUI mode). Event
// delivery uses a stored ErlNifPid, exactly as mob's NIF does.

#include <erl_nif.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// One window for the prototype. mob keys these by window id; the single-window
// case keeps the C simple while proving the mechanism.
static ErlNifPid g_window_pid;
static int g_have_pid = 0;

// GUI hook, provided by the host binary in GUI mode (resolved dynamically via
// -export_dynamic). Weak so the headless host links without it.
__attribute__((weak)) void rext_ui_render(const char *window, const char *json);

static ERL_NIF_TERM mk_bin(ErlNifEnv *env, const char *s, size_t n) {
    ErlNifBinary b;
    enif_alloc_binary(n, &b);
    memcpy(b.data, s, n);
    return enif_make_binary(env, &b);
}

static ERL_NIF_TERM render_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary win, json;
    if (!enif_inspect_binary(env, argv[0], &win) || !enif_inspect_binary(env, argv[1], &json))
        return enif_make_badarg(env);

    char *wbuf = (char *)malloc(win.size + 1);
    char *jbuf = (char *)malloc(json.size + 1);
    memcpy(wbuf, win.data, win.size);
    wbuf[win.size] = 0;
    memcpy(jbuf, json.data, json.size);
    jbuf[json.size] = 0;

    fprintf(stderr, "[rext_nif] render window=%s json=%s\n", wbuf, jbuf);
    fflush(stderr);

    if (rext_ui_render)
        rext_ui_render(wbuf, jbuf);

    free(wbuf);
    free(jbuf);
    return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM register_window_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    enif_self(env, &g_window_pid);
    g_have_pid = 1;
    fprintf(stderr, "[rext_nif] window process registered\n");
    fflush(stderr);
    return enif_make_atom(env, "ok");
}

// Deliver a UI event back to the window process. Called from the native UI (or
// from simulate_ui_event for testing). Message shape:
//   {rext_ui_event, <<Event>>, #{<<"tag">> => <<Tag>>}}
void rext_ui_emit_event(const char *event, const char *tag) {
    if (!g_have_pid)
        return;

    ErlNifEnv *env = enif_alloc_env();
    ERL_NIF_TERM ev_bin = mk_bin(env, event, strlen(event));
    ERL_NIF_TERM tag_bin = mk_bin(env, tag, strlen(tag));
    ERL_NIF_TERM key = mk_bin(env, "tag", 3);

    ERL_NIF_TERM params;
    enif_make_map_put(env, enif_make_new_map(env), key, tag_bin, &params);

    ERL_NIF_TERM msg = enif_make_tuple3(env, enif_make_atom(env, "rext_ui_event"), ev_bin, params);
    enif_send(NULL, &g_window_pid, env, msg);
    enif_free_env(env);
}

static ERL_NIF_TERM simulate_ui_event_nif(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
    ErlNifBinary ev, tag;
    if (!enif_inspect_binary(env, argv[1], &ev) || !enif_inspect_binary(env, argv[2], &tag))
        return enif_make_badarg(env);
    char ebuf[64], tbuf[64];
    snprintf(ebuf, sizeof(ebuf), "%.*s", (int)ev.size, ev.data);
    snprintf(tbuf, sizeof(tbuf), "%.*s", (int)tag.size, tag.data);
    rext_ui_emit_event(ebuf, tbuf);
    return enif_make_atom(env, "ok");
}

static ErlNifFunc funcs[] = {
    {"render", 2, render_nif, 0},
    {"register_window", 1, register_window_nif, 0},
    {"simulate_ui_event", 3, simulate_ui_event_nif, 0},
};

ERL_NIF_INIT(rext_nif, funcs, NULL, NULL, NULL, NULL)
