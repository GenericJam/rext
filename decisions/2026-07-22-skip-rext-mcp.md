# Skip rext_mcp — agents drive rext via dist, not an MCP server

- Date: 2026-07-22
- Status: accepted
- Supersedes the `rext_mcp` follow-up in
  `2026-07-20-rext-prototype-architecture.md` (§Consequences) and the "MCP server
  (planned)" language in the READMEs.

## Context

`rext_new` was emitting a `.mcp.json` pointing at a `rext_mcp.server` that didn't
exist, and several docs referenced a planned MCP server — both inherited from
`mob_new`/`mob_mcp` without rext actually needing them.

## Decision

**Do not build an MCP server.** Agents drive a rext app the same way mob does in
practice: `mix rext.connect` (or a plain `--name`/`--cookie` node) + `Rext.Test`
over Erlang distribution — connect, read `assigns`/`tree`, `click`/`input`,
inspect any process. That already gives an agent full logical drive/inspect.

## Why mob's rationale doesn't transfer

`mob_mcp`'s reason was the **sidecar** case: a native app written in pure
Swift/Kotlin with *zero Elixir*, driven by an agent that must not be able to
touch the BEAM — MCP's typed tools were the sandbox. **rext has no such user**: a
rext app *is* Elixir, so "hide the BEAM from the agent" has nothing to hide.

## When to revisit

Only if we want to drive a rext app from a **non-shell MCP client** (Claude
Desktop, Cursor, …) that can't run `elixir -e`/IEx. Not a need while the target
is Claude Code, which has the shell + dist.

## Consequences

- `rext_new` no longer emits `.mcp.json`; the generator + its test drop it.
- The dangling `rext_demo/.mcp.json` was removed.
- The real agentic gap is *visual* verification (the dist connection gives
  logical state, not pixels) — that, not MCP, is where the agentic pillar's next
  investment goes (see `PLAN.md` → per-platform agent visual verification).
