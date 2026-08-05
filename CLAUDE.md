# CLAUDE.md — medley (public plugin) contributor guide

This is the **public** Medley plugin repo. It contains only the thin, publishable plugin. The
mission **engine is a separate, private repo** (`Spine-AI/medley-engine`) that builds a
self-contained, code-signed binary. The binary is served from the **R2 CDN**
(`engine.getmedley.ai`) and mirrored to a **public GitHub Release on THIS repo** as a
fallback (so users download it with no auth), while the engine **source stays closed** — the release
workflow in the engine repo uploads the compiled binaries to both.

> Note: Claude Code does **not** load a plugin-repo `CLAUDE.md` into user sessions — this file is
> contributor guidance only. User-facing behavior comes from the skills under `plugin/skills/`.

## Hard rules

- **Never commit engine source or the built bundle here.** No `engine/`, no `src/`, no
  `dist/medley-engine.cjs`. Only the plugin (skills, hooks, scripts, manifests) and repo docs.
  (The compiled binaries live on GitHub **Releases**, not in the git tree.)
- **`plugin/engine/version` is the engine pin** — a plain-text version the plugin downloads. It is
  bumped BY HAND, in lockstep with `plugin/.claude-plugin/plugin.json` (and `.codex-plugin/plugin.json`),
  right after the engine's release CI mirrors that version to R2. The engine repo's CI is R2-only and
  does **not** bump it. See the engine repo's `RELEASE.md`.
- **Keep the product/plugin/marketplace name `medley`.** Install is `/plugin install medley`
  (the plugin name alone is enough — no redundant `@medley` qualifier). This is load-bearing, not
  cosmetic: the engine identifies its own MCP server by the `plugin_medley_medley` key
  (`engine/services/host-mcp.ts` `isMedleyServer`, `host-mcp-writer.ts` `RESERVED`) and both skills
  hardcode the `mcp__plugin_medley_medley__` tool prefix, so a rename makes the engine inject the
  orchestrator into its own workers. The Codex manifest keeps the same `name`; the two manifests must
  not drift on `name` or `version`.
- **Two hosts, one plugin.** Claude Code and Codex CLI (0.145+) install the same `plugin/` dir from
  two manifests — `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` — with the marketplace
  listed twice, in `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`. Anything
  host-specific belongs behind a runtime gate in the scripts (see `session-start.sh`'s `MEDLEY_HOST`),
  never in a forked copy of a file.

## Codex hook trust — the thing that will waste your afternoon

Measured on Codex CLI 0.145.0, because none of it is documented:

- A hook's `trusted_hash` in `[hooks.state."<plugin>@<market>:hooks/hooks.json:<event>:i:j"]` covers
  the hook's **command string** — not its matcher, and not the script's contents. So editing a
  matcher or a script body ships silently; changing a hook **command** invalidates trust.
- **An untrusted hook is skipped with no error.** Not a warning, not a log line — nothing. If a hook
  "isn't running", check for its trust entry before you debug the script. (This is why
  `session-start.sh` prints an explicit warning when a mission is live and the `Stop` entry is
  missing — see `mission-watch-gate.py`.)
- `codex exec` fires `SessionStart` and `PreToolUse` but **never `Stop`**, and never starts plugin MCP
  servers. Trust for an event that never fires is never granted, so `stop:0:0` cannot appear from a
  headless run. **`exec` is not a valid proxy for the TUI.**
- A same-version `codex plugin add`, and even a full `plugin remove` + `add`, did **not** materialise
  trust for a newly added `Stop` entry. Assume new hook events need an interactive TUI session.
- **Never cachebust the Codex manifest.** Codex names the cache dir after the version the **source**
  manifest declares and reconciles any disagreement by re-materializing and pruning — so a
  `+codex.<ts>` install directory is renamed out from under the next session, dangling every absolute
  path it bound at start. A local marketplace re-copies on a plain `codex plugin add` anyway.
- **`plugin/engine/version` uses the `X.Y.Z-dev.N` form for prereleases only.** `ensure-engine.sh`'s
  `vsort_desc` normalizes the literal `-dev.`; `-beta.`/`-rc.` would misorder and strand the
  engine-path pointer.

## How the engine is found (the one real mechanism)

A marketplace install **copies** the plugin into a read-only cache (`~/.claude/plugins/cache/...`),
**forbids `../` traversal** outside the plugin dir, and runs **no** install. So the engine is not
shipped in the plugin — a self-contained **binary** is downloaded on first session into the
persistent, writable `${CLAUDE_PLUGIN_DATA}/bin` dir. No auth, no Node, no npm.

- `scripts/resolve-engine.sh` — pure resolver. Order: `$MEDLEY_ENGINE` (dev, `.cjs` or binary) →
  `${CLAUDE_PLUGIN_DATA}/bin/medley-engine-<version>` → `~/.medley/engine-path` cache.
- `scripts/ensure-engine.sh` — SessionStart bootstrap. Reads `engine/version`, maps `uname`
  → asset (`medley-engine-darwin-arm64` — Apple Silicon only; x86_64 fails soft with a
  "requires arm64 / relaunch out of Rosetta" message), `curl`s it + `SHA256SUMS` from the R2 CDN
  (`engine.getmedley.ai/v<version>`) — falling back to this repo's GitHub Release —
  verifies the checksum, `chmod +x`, caches it. Advances the `~/.medley/engine-path` cache
  (`record_engine_path` — monotonic, never downgrades) and keeps the two newest binaries, pruning
  older ones (the engine deletes the rest down to one after it rolls — see engine `runDaemon`). No-ops
  for workers (`MEDLEY_WORKER=1`) and the dev override. Fails soft (session still starts).
- `scripts/mcp-headers.sh` — the `.mcp.json` **`headersHelper`** (see below). Emits the Bearer token
  for the daemon's `/mcp` (read-or-create from the stable `<dataDir>/mcp-token`, shared with the
  engine), nudges the daemon awake if the port isn't answering (cold-start bridge), and tags a worker
  session with `X-Medley-Worker`. Prints one JSON header object; must stay fast (10s CC budget).
- `scripts/run-engine.sh` — the **stdio fallback** transport (`run-engine.sh mcp` → the engine's
  `mcp` proxy) for Claude Code older than the http/`headersHelper` baseline, and the binary resolver
  `mcp-headers.sh` reuses. Not on the default path.
- `scripts/mcp-gateway.sh` — launches the `medley_gateway` server (`mcp --gateway`, your connected
  apps). Resolution is **pin-STRICT**: the binary the plugin is pinned to or nothing, because an older
  engine silently ignores `--gateway` and serves the ORCHESTRATOR under the gateway's name — duplicate
  mission tools, far worse than a clean failure. That is the one behavioral difference from
  `run-engine.sh`, which may fall back to `~/.medley/engine-path`.
  **One file, two install locations.** From `<plugin>/scripts/` it reads the manifest pin via
  `$DIR/..` (Claude Code). `session-start.sh` also installs it as `~/.medley/bin/medley-gateway` for
  hosts that hand an MCP server no plugin env (Codex), where it instead reads the fixed-path
  breadcrumbs `~/.medley/codex-engine-pin` + `codex-plugin-data`. Those fallbacks sit behind ONE gate
  that asks *which copy am I* **by location** (`$DIR` vs `~/.medley/bin`) — deliberately not by "did I
  find a pin", since an unpinned plugin dir must keep REFUSING rather than resolving against the other
  host's cache. On the Claude path the whole block is dead code; that equivalence is A/B-verified
  against the pre-Codex file and pinned by `test_mcp_gateway.sh`.
- `~/.medley/engine-path` — written ONLY by `ensure-engine.sh` (`record_engine_path`, which only ever
  ADVANCES it — so a stale older-pin session, e.g. a concurrent Claude Code window on a prior plugin
  cache, cannot downgrade the cache) so the **statusline** (wired via `settings.json`, where
  `${CLAUDE_PLUGIN_DATA}` is unset) can still find the engine. `session-start.sh` deliberately does
  NOT write it: a second, unguarded writer defeated the no-downgrade guard (that was the "engine-path
  stuck on an old version after `/plugin update`" bug).
- `~/.medley/state/update.json` — a download breadcrumb `ensure-engine.sh` writes while fetching a
  new engine (`{"state":"downloading","version","since"}`, epoch-ms; removed when the download
  settles). `statusline.sh` reads it — and the engine daemon's `.rolling` roll marker (60s freshness)
  — on a fast, engine-free path *before* delegating to `status --statusline`, so `/plugin update`
  surfaces `medley ▸ ⟳ downloading engine v…` / `medley ▸ ⟳ updating engine…`.

**`.mcp.json` is a DIRECT HTTP MCP server** (`type:"http"`, `url http://127.0.0.1:8730/mcp`) — Claude
Code talks straight to the shared daemon's `/mcp`, so CC's native HTTP auto-reconnect rides out a
daemon roll (engine auto-update) and the tools survive; the old per-session stdio proxy died on a
roll and broke them. The repo rides a **static** `X-Medley-Repo-Raw: ${CLAUDE_PROJECT_DIR}` header
(CC interpolates it; the `headersHelper` does NOT get `CLAUDE_PROJECT_DIR`); the token rides the
`headersHelper`. Requires the loopback port reachable — a stale pf redirect from an old
`service dashboard --setup --portless` breaks `127.0.0.1:8730`; clear it with
`medley-engine service dashboard --teardown` (`doctor` flags this). To revert to stdio for an old CC,
set `.mcp.json` back to `{ "command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/run-engine.sh","mcp"] }`.

Because paths must not leave the plugin dir after caching, **never** reintroduce a `../dist`
reference in a shipped file — always go through the resolver.

## Develop & test

- **Against a local engine build** (from the private repo): build it, then
  `MEDLEY_ENGINE=/path/to/medley-engine/dist/medley-engine.cjs claude --plugin-dir ./plugin`.
- **Installed mode** (what users get): `/plugin marketplace add <local path or Spine-AI/medley>` →
  `/plugin install medley` → new session downloads the engine binary into `${CLAUDE_PLUGIN_DATA}/bin`.
- **Validate** before pushing: `claude plugin validate ./plugin --strict`, the
  `plugin/scripts/test_*.sh` / `test_*.py` suites, and **`shellcheck -S info plugin/scripts/*.sh`**.
  Use that exact severity flag: CI runs a bare `shellcheck plugin/scripts/*.sh`, and apt's build
  reports **info**-level findings while brew's default threshold hides them — so a bare local run went
  green on an `SC2015` (`A && B || C`) that failed CI. Prefer `if/then` over `A && B || C` regardless.

### Under Codex CLI (0.142+ required, 0.145+ measured)

**0.142.0 is a hard floor.** `mcpServers` in `plugin/.codex-plugin/plugin.json` is camelCase-only from
0.142.0; ≤0.141 knows only snake_case `mcp_servers` and rejects the ENTIRE manifest on the unknown
key, so `codex plugin add` dies with a bare `Error: missing or invalid plugin.json` naming no field
and no file — while `codex plugin marketplace add` succeeds, which makes it read like a broken repo.
Bisected 2026-08-06: 0.138.0–0.141.0 fail, 0.142.0 → 0.147.0-alpha.6.5 install. **Never "fix" it by
renaming the key:** 0.142+ ignores that spelling and falls back to `plugin/.mcp.json`, silently
swapping the `--host codex` stdio launcher for the Claude wiring (http `:8730`,
`${CLAUDE_PLUGIN_ROOT}` paths, an unsupported `headersHelper`). Repro host-version questions against a
throwaway `CODEX_HOME=$(mktemp -d)` — every `codex plugin`/`mcp` subcommand honors it.


Codex has no `--plugin-dir`; it only loads plugins it has **copied** into `~/.codex/plugins/cache`
from a configured marketplace. So the loop is reinstall → **new thread** (tools bind at thread
start), wrapped up as:

```
scripts/codex-dev-install.sh                                           # downloaded engine
scripts/codex-dev-install.sh ../medley-engine/dist/medley-engine.cjs   # local build
scripts/codex-dev-install.sh --clear-engine
```

The local-build pin is `~/.medley/engine-override`, **not** `$MEDLEY_ENGINE`: a Codex plugin MCP
server inherits no session environment at all (measured — see `plugin/scripts/medley-mcp.sh`), which
is also why the Codex manifest launches `~/.medley/bin/medley-mcp` rather than anything under the
plugin dir. `session-start.sh` installs that fixed-path launcher from either host.

**There is no `/mission` on Codex.** Codex plugins cannot contribute slash commands, and skills use
the `$` prefix namespaced by plugin — so the invocation is **`$medley:mission`** / `$medley:dashboard`,
or just state the goal (Codex also triggers a skill on description match).

**Editing `plugin/` does nothing until you reinstall** — Codex runs its cache copy, never the source.
`codex plugin list` shows the *source* version, so it will happily report a version you are not
running; `ls ~/.codex/plugins/cache/medley/medley/` is the honest check.

**The cache dir name must always equal the source manifest's version.** When they disagree, a session
bound to the old directory loses every path it captured: `session-start.sh` fails to exec (**hook
exited with code 127**) and `edit-conflict-gate.py` makes python exit **2** — which is exactly the
"PreToolUse denied" signal, so a missing file surfaces as a *blocked tool call* with a Python
traceback as the denial reason. If you see that pair, the cache dir was renamed mid-session.

**The engine updates itself the same way on both hosts.** Codex gives plugin *hooks* a real writable
data dir (`~/.codex/plugins/data/medley-medley`, mapped onto `CLAUDE_PLUGIN_DATA`) and fires
`SessionStart`, so `ensure-engine.sh` downloads whatever `plugin/engine/version` pins and the daemon
rolls to it. But `~/.medley` is **shared**: one state dir, one daemon, one port — don't run Codex and
Claude Code against different engine builds at the same time.

Two Codex-only wrinkles in that update path, neither of which affects Claude Code:
- **The pin's fast path is Claude-only.** `X-Medley-Engine-Pin` is emitted by `mcp-headers.sh`, i.e.
  CC's `headersHelper`; Codex's transport (`mcp --host codex` → `mcpProxyHeaders`) does not send it. So
  the daemon's event-driven "converge to the pin" trigger never fires from a Codex session and
  convergence falls back to the hook-side download plus the daemon's 15-minute sweep.
- **A daemon roll mid-thread kills Codex's bridge.** The stdio proxy exits when the daemon goes away
  (`up.onclose = exit`), whereas CC's direct-http entry 404-reinitializes and survives. Whether Codex
  respawns a dead plugin MCP server is unverified; worst case that thread loses its mission tools until
  a new one starts.

## Uninstall — three paths, one list

Neither host has a plugin-uninstall lifecycle hook, so `/plugin uninstall medley` /
`codex plugin remove` clears only that host's registry + cache. Everything else is cleaned up by one
of three paths, and all three read the SAME classification from the engine's
`engine/services/purge-plan.ts`:

1. **Automatic (the default).** The running daemon is the only actor that survives the removal (its
   binary's inode outlives the unlink), so it detects the orphaned state on its 30s sweep
   (`orphan-teardown.ts`) and tears itself down: bootout its LaunchAgent, purge every regenerable
   artifact (~250MB — both hosts' downloaded binaries, the trampoline, the TCC-stable link, the shims
   and breadcrumbs), then exit. Mission history / `config.toml` / BYOK keys are KEPT — unless there is
   nothing worth keeping (no missions, no keys), in which case `~/.medley` goes too and a try-once
   install leaves zero trace. `MEDLEY_ORPHAN_PURGE=0` tears down without purging.
2. **`medley-engine service uninstall --all [--keep-data]`** — the same purge plus hosts/pf teardown.
3. **`plugin/scripts/uninstall.sh`** — that, plus each host's cache/marketplace, the `~/.codex/config.toml`
   tables, the shell alias and the `settings.json` statusLine.

Five things to keep in mind when editing any of it:

- **The trigger requires BOTH hosts.** One shared daemon serves Claude Code and Codex and both
  channels, so `installedOnAnyHost` must read `~/.claude/plugins/installed_plugins.json` AND
  `~/.codex/config.toml`, matching the plugin name exactly (`key.split('@')[0]`, and the
  `[plugins."medley@` prefix). Consulting only Claude Code's registry — which it used to — tore the
  daemon down out from under a live Codex install.
- **The list is an allowlist-to-DELETE.** Anything unclassified is KEPT. A file a future engine version
  starts writing then survives an uninstall it was never classified for; the reverse polarity risks
  someone's mission history. A test asserts `keep ∩ purge = ∅`.
- **Plugin-data dirs are claimed by OWNERSHIP, never by name.** A dir is `<plugin>-<marketplace>`, so a
  third-party `medley-foo@bar` matches a `medley-*` glob. `isOwnedDataDir` requires a
  `bin/medley-engine-*` inside. (The old code instead derived one dir from the running binary and gated
  it on `basename === 'medley-medley'`, which stranded ~83MB on the dev and inline channels.)
- **`uninstall.sh` keeps a hand-written copy of the list** — it must work when no binary resolves at
  all, which is exactly when a user needs it. It prefers `service purge-plan --paths` (tab-separated so
  no jq/python is required) and falls back to two marked heredocs. The engine's
  `__tests__/purge-plan.test.ts` diffs the two and fails on drift; it skips when the plugin repo isn't
  checked out beside the engine, so run the engine suite after touching either file.
- **Ordering is load-bearing.** The LaunchAgent is removed FIRST and the purge is abandoned if that
  fails: without the plist gone, KeepAlive relaunches into a purged install and execs a trampoline
  whose target we just deleted. Leaving everything in place keeps the understood failure mode (exit 78,
  launchd throttles).

## Layout

```
.claude-plugin/marketplace.json   the "medley" marketplace (lists this plugin, source ./plugin)
.agents/plugins/marketplace.json  the same, for Codex (root = repo root; add with `codex plugin
                                  marketplace add .`)
scripts/codex-dev-install.sh      Codex dev loop (validate → codex plugin add → restore)
plugin/.claude-plugin/plugin.json manifest (identity metadata: name, version, author, license, …)
plugin/.codex-plugin/plugin.json  Codex manifest — inline mcpServers (medley + medley_gateway, both
                                  via ~/.medley/bin launchers), no `hooks` key (its validator rejects
                                  one; the runtime finds hooks/hooks.json by path anyway)
plugin/.mcp.json                  http MCP server → daemon /mcp (headersHelper: scripts/mcp-headers.sh)
plugin/hooks/hooks.json           SessionStart/PreCompact → session-start.sh; PreToolUse gate;
                                  Stop → mission-watch-gate.py (Codex supervision backstop)
plugin/scripts/                   {resolve,ensure,run}-engine.sh, session-start.sh, statusline.sh,
                                  edit-conflict-gate.py, medley-mcp.sh (installed to the fixed path
                                  ~/.medley/bin/medley-mcp for hosts with no plugin env — Codex),
                                  mcp-gateway.sh (the pin-strict gateway launcher; ALSO installed to
                                  ~/.medley/bin/medley-gateway, breadcrumb-resolved — see above),
                                  mission-watch-gate.py (Codex Stop-hook backstop),
                                  uninstall.sh (complete teardown — run BEFORE the host's own
                                  uninstall, which deletes the cache this script lives in),
                                  strip-codex-config.py (uninstall: ~/.codex/config.toml tables)
plugin/engine/version             engine version pin (hand-bumped in lockstep with both manifests)
plugin/skills/mission|dashboard   the /mission and /dashboard skills (+ hosts/ supervision rationale,
                                  runtimes/ routing guides)
```
