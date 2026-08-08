%% rext_nif — NIF stub for the in-process render backend.
%%
%% Loaded by the embedded BEAM inside the native host binary. Mirrors mob's
%% `mob_nif.erl` role: declare the NIF surface, load the shared object, and
%% raise a clear error if a function is called before the NIF loaded.
%%
%% The .so path comes from REXT_NIF_PATH (set by the host) or defaults to
%% "rext_nif" resolved against the load path.
-module(rext_nif).

-export([render/2, register_window/1, simulate_ui_event/3]).
-nifs([render/2, register_window/1, simulate_ui_event/3]).
-on_load(on_load/0).

%% Loading is best-effort: apps that never select the NifBridge transport
%% (the socket Bridge is the default) still preload every module at boot in a
%% release's default `embedded` mode, so a missing .so/.dll must not be fatal —
%% only crash if a NIF is actually called (via the `nif_not_loaded` fallback
%% clauses below).
on_load() ->
    Path =
        case os:getenv("REXT_NIF_PATH") of
            false -> "rext_nif";
            P -> P
        end,
    case erlang:load_nif(Path, 0) of
        ok -> ok;
        {error, {load_failed, _}} -> ok;
        {error, Reason} -> {error, Reason}
    end.

%% Push a rendered frame (JSON binary) for a window to the native UI.
render(_WindowId, _Json) -> erlang:nif_error(nif_not_loaded).

%% Register the calling process as the owner of WindowId. Called from the
%% window process so the NIF captures its pid (enif_self) for event delivery.
register_window(_WindowId) -> erlang:nif_error(nif_not_loaded).

%% Test/agent hook: invoke the native "UI emitted an event" path, which sends
%% the event back to the registered window process via enif_send — exercising
%% the return path without a real click.
simulate_ui_event(_WindowId, _Event, _Tag) -> erlang:nif_error(nif_not_loaded).
