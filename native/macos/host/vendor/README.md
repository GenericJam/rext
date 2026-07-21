# Vendored static libraries (in-process host)

These are the two components OTP compiles directly into `beam.smp` and does
**not** ship as linkable archives, so embedding `erl_start` (the in-process NIF
host) needs them built from OTP source:

- `libepcre.a` — OTP's *patched* PCRE2 (built with `-DERLANG_INTEGRATION`;
  provides `pcre2_set_loops_left_8` etc. that stock/system PCRE2 lacks).
- `libryu.a` — OTP's vendored Ryu float formatter (`d2s.c`).

**Arch:** `arm64` macOS. Rebuild for another arch/OTP from the matching OTP
source using the recipe in
`decisions/2026-07-20-in-process-nif-host.md`.

**Provenance / licenses:** compiled from Erlang/OTP 29.0 sources. OTP is
Apache-2.0; PCRE2 is BSD; Ryu is Apache-2.0 / Boost. Redistribution of the
compiled form is permitted under those terms.

Everything else about the in-process host is built by `../build.sh`; only these
two are vendored because they'd otherwise require a full OTP source checkout.
