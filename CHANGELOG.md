# Changelog

All notable changes to pwt (Power Worktrees) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.13] - 2026-08-24

### Added
- `pwtfile_stop_jobs <command>` (alias `stop_jobs`): stops this
  worktree's running background jobs of one command through the job
  registry. Ships the kill-delegation contract as a two-line guard
  instead of 30 lines everyone writes wrong: the registry filter
  (worktree + command) is what keeps a shared worker in another worktree
  untouched, where pkill-by-name would kill them all.
- The kill-delegation contract is now stated where discovery actually
  looks: `pwt help pwtfile` (semantics + guard), the agent skill (as a
  rule for writing Pwtfiles), `examples/Pwtfile.reference` (a worker
  section covering the stop side of shared vs isolated queues), and the
  README example. Audit finding: every surface named `PWT_KILL_TARGET`,
  none said what honoring it means, and the tool's own author shipped a
  Pwtfile whose kill delegation started a worker.

### Fixed
- `pwt statusline install` works again: the plugin still called the
  core's `sed_inplace` helper, but a plugin execs as its own process
  and cannot borrow core functions, so every install died with
  "command not found" since statusline moved out of the core. The
  helper is now defined in the plugin's self-contained block.
- Two background launches of the same fast command in the same second no
  longer overwrite each other's job record: the id (which embeds a
  whole-second timestamp) is bumped until free.
- `pwt jobs`/`pwt logs` survive a `PWT_DIR` containing a space: two
  newest-first scans word-split `$(ls -t)` and lost every path.
- An invalid `--count` is a usage error instead of silently launching 1
  instance (`--count abc`, `--count 0`, `--count=junk` all rejected).
- The project index notices a config edited in the same second as the
  cache write (freshness now requires the cache to be strictly newer)
  and notices a renamed project directory (the projects dir mtime joins
  the staleness check). Both used to serve stale entries forever.
- `workspace_link` pointing at a real directory is reported loudly; it
  used to silently drop the symlink INSIDE the directory.
- `pwt remove` asks its uncommitted-changes confirmation BEFORE running
  `--kill-*` delegations: an aborted remove had already killed the
  worktree's servers and workers.
- `pwt self use npm` works again: an unmatched nvm glob killed the run
  under pipefail before any fallback, and the fallback itself used
  `npm bin -g`, removed in npm 9 (now `npm prefix -g`).
- `pwt gateway init` rejects ports outside 1-65535; the numeric check
  alone let 0 and 70000 through to fail only at bind.

### Added
- Test coverage the August review flagged as missing: gateway port
  validation, the whole `pwt self use` path, and every fix above landed
  red-first.

### Changed
- `pwt server` stops announcing "Starting server on port N" as fact when
  the Pwtfile's `server()` never reads `$PWT_PORT` (comments do not
  count). A server command may deliberately bind a fixed port (a browser
  extension has its URL baked in); pwt only controls the allocation, so
  it now says so: "allocated port N; this Pwtfile's server() picks its
  own".

## [0.2.12] - 2026-08-19

### Added
- `pwt doctor` reports which installation actually answers when you type
  `pwt`: a warning with both paths and versions when the first pwt on
  PATH is not the binary running, a note when no pwt is on PATH at all,
  and a pointer to `pwt self`. Motivated by an hour spent debugging
  fixes that were correct all along while the terminal ran an npm
  0.2.8 that shadowed the development symlink. When no local pwt can be
  trusted, `npx @jonasporto/pwt@latest doctor` runs the latest published
  doctor with no install; the stale-wrapper error and doctor both point
  at it.

### Fixed
- A stale shell wrapper no longer deadlocks the shell. The function
  bakes the binary's path at generation time; when that install
  disappeared (an npm or brew copy removed), every `pwt` call errored
  AND `source ~/.zshrc` could not heal it, because the eval line calls
  the broken function itself (functions shadow PATH binaries). The
  wrapper now falls back to the first `pwt` on PATH when the baked path
  is gone, so a stale function regenerates itself; with no binary
  anywhere it exits 127 with a reinstall hint instead of a raw path
  error. One-time recovery for already-broken shells:
  `unfunction pwt; source ~/.zshrc`.

## [0.2.11] - 2026-08-19

### Fixed
- The shell wrapper bypassed the 0.2.10 name-vs-command precedence: it
  kept a project fast path that cd'ed before ever consulting the binary,
  so `pwt ports` still navigated in a real terminal while every test
  (which calls the binary) passed. The wrapper no longer decides
  anything itself; the `_implicit-cd` probe is the only cd path. Reload
  the wrapper (open a new shell) to pick this up.
- The wrapper never probed bare `pwt --project <name>`, so the explicit
  route the collision warning advertises printed the path instead of
  navigating, in a real shell, even after the 0.2.10 binary fix. Caught
  only when the wrapper-level test was written; the binary-level test
  had passed all along.
- The wrapper helpers (`_pwt_is_project`, `_pwt_detect_project`) read
  `~/.pwt` literally, ignoring `PWT_DIR`. That is also why the test
  sandbox could never catch the bypass.
- The terminal-title escape sequence leaked into captured stdout when
  the shell function ran without a terminal (pipes, scripts, tests). It
  is now emitted only when stdout is a tty.

## [0.2.10] - 2026-08-19

### Changed
- A project named after a builtin command now resolves to the command,
  with a stderr warning naming the project's own routes (its alias, or
  `--project`). It happened for real: a project called `ports` predated
  0.2.8 turning the word into a command, and shadowed the registry
  entirely. Worktrees have followed this precedence since 0.2.5; projects
  were the one class that did not. Aliases and `--project` are unchanged,
  and non-colliding names resolve exactly as before. The command list
  moved into one shared `is_builtin_command()` so the next check cannot
  grow its own copy.

### Fixed
- Bare `pwt --project <name>` now navigates to the project's main
  checkout through the shell wrapper. It used to print the path and
  leave you where you were, which mattered once it became the explicit
  route the collision warning advertises.

## [0.2.9] - 2026-08-17

### Fixed
- A port held by a macOS system daemon no longer reads as a running dev
  server. AirPlay Receiver (ControlCenter) binds 5000 and 7000 by
  default, which is where Flask, Rails and most base-port conventions
  start, so `pwt ports` and `pwt servers` reported "listening" on a
  machine with nothing running. The filter existed in one place only
  (`pwt list -v`); it is now a single classifier used by every occupancy
  check, including the gateway probe.
- `pwt remove` refused to remove a worktree because a system daemon held
  its port, and `--kill-port` would `kill -9` that daemon. On macOS the
  target was ControlCenter. System processes are now skipped entirely:
  never a blocker, never a kill target.
- `pwt info` reported the worktree's server as running, with the system
  daemon's pid.
- `pwt server wait` returned "Ready" instantly when a system daemon held
  the worktree's port, since the daemon answers the TCP probe. It now
  exits 1 with the reason and a way out, rather than telling an agent a
  server exists when none does.
- `pwt list -v` checked the main checkout on a hardcoded port 5000
  instead of the project's own `base_port`, so any project not using the
  default was reported against somebody else's port.

### Added
- `pwt ports` reports `system` as a distinct status, with `"system"` in
  `--json`, and explains how to free the port.

## [0.2.8] - 2026-08-17

### Added
- `pwt fix-port` also resolves *registry* conflicts, not only a busy
  port. Two records holding the same port with nothing running used to
  be answered with "already free, no changes needed", which is exactly
  the state a machine accumulates: the collision is queued, not live.
  It now names the other claimants and reallocates (non-interactive runs
  reallocate directly), and points at `pwt repair` when the project's
  hooks generate files from the port.
- `pwt ports`: machine-wide port registry. Lists every port pwt has
  allocated across all projects with its owning worktree, whether
  something is listening, and whether two records claim the same port
  (`--json` for scripts). Answers "who owns 8001" without visiting each
  project.

### Fixed
- Port allocation is machine-wide. It used to consult only the current
  project's records plus the live system check, so two projects that both
  started at 8000 were handed the same port, and the clash surfaced only
  the day both servers ran at once (a not-yet-running server is invisible
  to `lsof`). Allocation now also avoids every other project's
  allocations and every project's declared base port. Existing
  overlapping records are reported by `pwt ports` and fixed with
  `pwt fix-port`.
- The man page announced `pwt 0.1.9` since February and the README badge
  drifted for the same reason: `scripts/release.sh` edited them but never
  staged them. Both are updated and committed by a release now, and
  `scripts/check` compares the man page's version alongside `bin/pwt`,
  `package.json` and the README badge.

## [0.2.7] - 2026-08-16

### Fixed
- `pwt doctor` made a network call even when nobody was watching. The
  version check now runs only for an interactive terminal; unattended
  runs (CI, scripts, agents, test harnesses) read the cached value and
  make no request. Besides the wasted round-trip, the curl child
  inherited the caller's pipes, which is how a harness ends up waiting
  on pwt: the full suite under the CI nounset job stopped finishing.

## [0.2.6] - 2026-08-16

### Added
- Update notice where you would actually see it. `pwt doctor` now reports
  the running version and whether a newer release exists (it pays the
  network check and refreshes the shared cache), and `pwt create` prints a
  one-line notice on stderr when the cached version is newer. The notice
  is rate limited to once a day, never appears under `--no-input`, for
  agents, or when output is not a terminal, and the cache refresh happens
  in a detached background process so no command waits on the network.
  `PWT_NO_UPDATE_CHECK=1` disables notice and refresh entirely.
  Previously the check existed but only ran in `pwt version`, which meant
  a machine that never typed `pwt version` never learned about a release.

### Fixed
- `pwt for-each` aggregates per-worktree exit codes: it now ends with
  `✗ Command failed in N of M worktrees: <names>` and a non-zero exit
  instead of an unconditional checkmark that hid every failure. Its help
  also claimed the main checkout was skipped; it runs there first and
  the help now says so.

## [0.2.5] - 2026-08-16

### Changed
- `pwt tree` (default variant) joins the list cache contract: served
  instantly even when stale, recomputed in a detached background run,
  `tree --refresh` recomputes synchronously, and flagged variants
  (`--all/--dirty/--ports/--short`) always render live. Rows compute in
  the same parallel pool as `pwt list`. Measured: 12.9s → 0.05s warm.
- `pwt servers` takes one listening-ports snapshot (single lsof/ss call)
  and one pass over the job files instead of one lsof probe plus a full
  job-directory scan per worktree. Measured: 11.7s → 1.9s.
- `pwt state --json` emits values through fork-free escape helpers; the
  per-key command substitutions cost ~3 forks a line across every record.
  Measured: 2.4s → 0.5s.
- Cache writes are atomic (temp file + rename), and `list --refresh` no
  longer deletes the cache before regenerating: concurrent readers used
  to have a window where the cache file simply did not exist. Caught by
  the new stale-serving test suite.
- `pwt list` reads never block on recomputation: a stale cache is served
  instantly (milliseconds) and the recompute runs in a detached
  background pwt that rewrites the cache for the next read, with a
  stderr note showing the served age. First-ever runs and `--refresh`
  stay synchronous; `PWT_LIST_ASYNC_REFRESH=0` restores blocking.
- `pwt list --porcelain` (the format agents poll) is now cached under
  the same contract as the table view and computes rows in the same
  parallel pool. Measured on a 66-worktree project: 13.3s every call
  before; now 9.2s cold and 0.03s from cache. The JSON gained a
  top-level `generated_at` (epoch) field so consumers can judge the
  document's freshness; metadata writes invalidate this cache too.
- `pwt list` recompute path is substantially cheaper. Measured on a real
  66-worktree Rails project: `list --refresh` 16.5s → 12.7s. The status
  walk now runs once per row instead of twice (`check_merge_status`
  accepts the row's pre-captured porcelain), `get_status_symbols` parses
  one `git status --porcelain` in bash instead of three git commands
  piped through `wc | tr` (752 `tr` forks eliminated per list),
  divergence uses one `--left-right --count` call instead of two, hash
  and age share one `git log` call, `visual_width` answers ASCII cells
  without forking, and the row pool is a rolling window sized up to 8
  by core count instead of a batch-of-4 barrier.
- `pwt list` fetches the remote at most once per 60s
  (`PWT_LIST_FETCH_TTL`); `list --refresh` still always fetches. The
  fetch cost ~3s per list against a real remote and dominated lists
  that missed the row cache (any metadata write clears that cache).

### Fixed
- A worktree whose name contains a command name (e.g. `skill-refactor`)
  hijacked that command through the shell wrapper's navigation probe:
  `pwt skill` changed directory instead of printing the guide. `skill`
  joined the implicit-cd blocklist, and a new sync test asserts every
  completion-listed command is in that blocklist, so the next new
  command cannot reintroduce the class.

## [0.2.4] - 2026-08-15

### Added
- `pwt meta unset [worktree] <field>`: remove a custom metadata field
  (phase, reviewer, marker, ...). Structural fields (path, branch, port,
  base, base_commit, created_at) are refused. Without a worktree argument
  the target is resolved from the current directory. Previously an empty
  value was read as a get, so fields could never be cleared; external
  consumers (dashboards) were blocked on this.

### Fixed
- The `pwt meta <key> [value]` shortcut now targets the worktree you are
  standing in; the current-symlink worktree is only a fallback when the
  shell is outside any worktree. Previously the symlink won, so running
  the shortcut inside worktree A silently read/wrote worktree B. The
  shortcut also works from subdirectories of a worktree now.

## [0.2.3] - 2026-08-15

### Fixed
- Running `pwt init` with shell integration active registered a ghost
  project named `_implicit-cd` pointing at the current repo: the shell
  wrapper's navigation probe (`pwt _implicit-cd init`) matched the
  `pwt <name> init` form. Internal `_*` command names are now excluded
  from project registration. Cleanup for affected users:
  `rm -rf ~/.pwt/projects/_implicit-cd`.

## [0.2.2] - 2026-08-15

### Added
- `pwtfile_git_exclude` (Pwtfile helper, alias `git_exclude`): declare
  worktree-only git ignores from the Pwtfile. Patterns are appended
  idempotently to the repo's `.git/info/exclude` (common dir), so they are
  never committed and one call covers every worktree of the repo. Useful for
  per-worktree generated files such as `pnpm-lock.yaml` derived from a yarn
  project.

### Changed
- `--bg` launch output now offers `pwt jobs wait <id>` first, before the logs
  and stop hints. Session logs showed agents hand-rolling `until ... sleep`
  loops (251 sleeps and 75 until-loops across 23,770 commands) while the wait
  primitives were used 5 times, so the hint has to appear where the wait
  decision is made.

## [0.2.1] - 2026-08-13

### Added
- Agent discovery surfaces: `llms.txt` on the project site, a
  "When pwt beats raw git worktree" decision table in the README, and a
  matching when-to-suggest section in the shipped agent skill.

### Fixed
- `pwtfile_replace_re` could not write a replacement containing `/`. Pattern
  and replacement were interpolated into perl's `s///`, so any filesystem
  path (`DATABASE_URL`, `REDIS_URL`, a socket path: the common case when
  rewriting a `.env`) closed the substitution early. perl aborted with
  "Unknown regexp modifier", the file was left untouched, and pwt reported
  success. Both are now passed to perl as arguments. The replacement is a
  literal string, so `$1`-style backreferences are no longer expanded.
- Pwtfile hooks printed `✓ <label> (<phase>) completed` unconditionally: a
  `setup()` that died halfway looked exactly like one that worked. The line
  now reflects the hook's exit status (`⚠ ... failed (exit N)`), and signal
  terminations (130/143) still count as normal, since Ctrl-C is how a
  foreground server is stopped. A failing hook still does not abort worktree
  creation.
- `examples/Pwtfile.reference` rewrote `.env` keys with `pwtfile_replace`,
  a substring swap: on a file already containing `PORT=3000` the documented
  recipe produced `PORT=50013000`. The reference now uses the line-anchored
  `pwtfile_replace_re` form.

## [0.2.0] - 2026-08-10

Minor (not patch) because the internal state format changed and commands were
removed. External consumers of `~/.pwt` should read `state-version` and
`docs/state-v2-contract.md`.

### Added
- `pwt state --json`: versioned snapshot of all state (projects, worktrees
  with metadata, background jobs) for external consumers.
- `pwt state migrate` (alias `pwt migrate`) with `--status`, `--check`
  (read-only dry run), `--verify` and `--porcelain`. Migration process and
  per-schema guides in `docs/migrations/`.
- `pwt jobs wait <id|worktree>` and `pwt server wait [worktree]`
  (`--log-contains`, `--timeout`): block until ready instead of poll loops.
- `pwt jobs list --porcelain`: JSON job list, the supported way for scripts
  and Pwtfiles to enumerate jobs.
- Pwtfile `doctor()` hook: `pwt doctor` runs project-defined health checks.
- Pwtfile `branch_name()` hook: a project can own its branch-naming
  convention (`--branch` still wins; empty output falls back to the default).
  See `examples/Pwtfile.reference`.
- `pwt skill`: prints the agent-facing CLI guide (`--path` for the file
  location, `--install` to copy it into agent skill directories).
- `skills/pwt-cli/SKILL.md`: agent-facing CLI guide, kept in sync with help
  and README by a rule in CLAUDE.md.
- Exit codes 5 (timeout) and 6 (missing dependency).

### Changed
- **State format v2**: internal state moved from JSON to flat key=value files
  (`state/<project>/<worktree>.meta`, `projects/<name>/config`,
  `jobs/<id>.job`), plus an append-only `events.log`. `~/.pwt/state-version`
  declares the schema; legacy state migrates automatically on first run and
  originals are kept as `*.v1.bak`. See `docs/state-v2-contract.md`.
- **`jq` is no longer a runtime dependency** (~132 call sites removed); it is
  used only for the one-time v1 migration. Startup dropped from ~250ms to
  ~25ms.
- `fzf` is now optional: `pwt select` and `use --select` fall back to a
  builtin picker.
- Port detection falls back to `ss`, `fuser` and a bash `/dev/tcp` probe when
  `lsof` is absent (previously it assumed the port was free).
- `column -t` replaced by a pure-bash formatter (absent on slim Linux).

### Fixed
- Background daemons no longer inherit the caller's file descriptors, which
  made any Linux caller capturing pwt's output block until the daemon exited.
- `pwt server <arg>` inside a worktree reached through the project's `current`
  symlink treated the argument as a worktree name (`pwt server stop` failed).
- `pwt doctor` reported "Pwtfile: not found" for a Pwtfile declared in project
  config, and now distinguishes "declared but missing".
- Statusline installer used BSD-only `sed -i ''`, breaking it on Linux (the
  installer now lives in the `pwt-statusline` plugin).
- Gateway returned an undefined `EXIT_DEPENDENCY`, crashing the error path
  under `set -u` when node was absent.
- The v1→v2 migration checked `jq` failures only for `meta.json`: a malformed
  project `config.json`, `gateway.json`, job or trash file silently became an
  empty conversion sealed by the `.v1.bak` rename. Malformed files are now
  left unconverted, reported, and picked up by `pwt state migrate`.
- Concurrent first runs after the upgrade could interleave the auto-migration
  (it had no lock and shared a fixed staging file); it now serializes behind
  an `mkdir` lock and stages per-process.
- `pwt shell-init` emitted a function pointing at the *installed* pwt instead
  of the binary that generated it, silently mixing versions.

### Removed
- `pwt status` (the bash TUI dashboard). The command now exits with a pointer
  to `list`/`tree`/`servers`.
- `pwt ai` and the `-a`/`--ai` flag on `create`/`track`/`add`: starting an AI
  tool is the editor's or a Pwtfile command's job, not core pwt's.
- `pwt open`: use your platform opener on `pwt current` /
  `$(pwt info --porcelain)` paths instead.
- The bundled `pwt-aitools` plugin (`topology`, `context`).
- `claude-setup`/statusline moved out of core into the `pwt-statusline`
  plugin (`pwt statusline ...` once the plugin is installed).

## [0.1.14] - 2026-08-05

### Added
- Worktree-first dispatch: `pwt <worktree>` with no command jumps straight to
  that worktree (implicit `cd`), and `pwt <worktree> <cmd>` runs the command
  there.
- `pwt logs [worktree] [-f]` for viewing background job logs.
- `pwt self` (aliases: `pwt versions`, `pwt which`) to list installed pwt
  versions and switch the active one (`pwt self use <local|npm|brew|path>`).
- `--count N` for background commands: launches N indexed jobs
  (`-1`..`-N`) with `PWT_JOB_INDEX` exported to the Pwtfile.
- `pwt adopt --all [dir]` for bulk-adopting unregistered worktrees.
- `post_use()` Pwtfile hook, run after `pwt use` (including `@`).
- `workspace_link` project config: keeps a friendly stable symlink pointing at
  the current worktree.
- `pwt editor --pinned [worktree]` opens the stable current symlink instead of
  the resolved worktree path.
- Generic Pwtfile command delegation: `pwt <custom> --help` prints the
  Pwtfile comment block instead of executing the function; `pwt server --help`
  shows project flags documented in the Pwtfile.
- `pwt info --porcelain` / `--json` structured output, including background
  `jobs[]`; `pwt servers` shows per-worktree background jobs.
- "Scripts/agents" section in `pwt help` (porcelain output, `--no-input`,
  exit codes).

### Changed
- Startup is ~10x faster (~250ms → ~25ms): project detection now uses a
  single-`jq` project index cached on disk (`$PWT_DIR/cache/project-index`).
- `pwt ps1` no longer spawns git/jq per prompt.
- `pwt list --refresh` computes rows in parallel batches.
- Background/gateway operations poll at 50ms instead of fixed sleeps
  (`--bg` grace configurable via `PWT_BG_GRACE_SECONDS`).
- Guards that skip an already-running server now warn about ignored flags and
  print the exact restart command.

### Fixed
- `pwt create X main` no longer rewrites the base to `origin/main` when no
  remote exists; failed fetches are no longer silently swallowed.
- `pwt create --branch X` reuses an existing local branch with a warning
  (and shows how far behind the base it is) instead of failing.
- `pwt copy` patterns containing `/` now match paths (e.g. `src/*.js`), and
  `.git`/`node_modules` are pruned from the search.
- `pwt run <name> <cmd>` errors when `<name>` is neither a worktree nor a
  known command instead of silently running on the main app.
- `pwt <custom> --bg` now daemonizes correctly (execution-flag stripping no
  longer happens in a subshell).
- `pwt editor` no longer crashes with `EDITOR: unbound variable`.
- `pwt status` without a TTY aborts cleanly instead of leaking alt-screen
  escapes and crashing on `/dev/tty`.
- `pwt discover` normalizes paths (`pwd -P`), so `/tmp` vs `/private/tmp` no
  longer marks configured projects as unconfigured.
- Removing the current worktree now falls back to the previous worktree (or
  `@`) instead of leaving a dangling `current` symlink.
- `pwt gateway init --port` validates the port is free; `gateway use` no
  longer records a new target when the daemon failed to start.
- Trash directory honors `PWT_DIR` instead of hardcoding `~/.pwt/trash`.
- Shell wrappers no longer print `_pwt_is_project: command not found` noise.
- Implicit cd never treats flags as worktree names (`pwt --version` and
  hyphenated typos no longer fall into a surprise fzf picker) and never opens
  fzf from the shell-wrapper probe.
- `pwt server <arg>` probes worktree names without saving navigation state or
  opening fzf, so positional Pwtfile args can't hang in a hidden picker.
- One malformed `config.json` no longer breaks project/alias resolution for
  every other project (index rebuild skips just the broken one).
- `pwt alias <name>` invalidates the project-index cache, so the new alias
  works immediately.
- `pwt self use` resolves file-level symlinks and refuses to point
  `~/.local/bin/pwt` at itself (previously bricked every pwt invocation with
  "too many levels of symbolic links" when run through the managed link).
- `pwt list` no longer silently drops the row of a corrupted worktree.

## [0.1.13] - 2026-06-05

### Added
- `gateway_host` project config and `pwt gateway init|up --host <host>` for
  choosing the public gateway URL host.

### Fixed
- Gateway URLs now default to `localhost` instead of `127.0.0.1` so browser
  cookies and sessions are shared with direct local app URLs on `localhost`.

## [0.1.12] - 2026-06-05

### Added
- `pwt track <remote-branch>` for creating a prepared worktree that tracks an
  existing remote branch without applying `branch_prefix`.
- `pwt adopt [path]` and `pwt setup [path]` for registering existing Git
  worktrees with pwt metadata, ports, and setup hooks.
- `pwt gateway` for a stable per-project local gateway URL that can route to
  any worktree server.
- `pwt servers` for project-wide visibility into gateway target, active ports,
  current worktree, and background server jobs.
- Parallel BATS runner via `scripts/test.sh` and `make test`.

### Changed
- Worktree path resolution now honors metadata paths so adopted worktrees can
  live outside the configured `worktrees_dir`.
- Shell completions, man page, and README now document tracking, adopting,
  gateway, servers, and `gateway_port`.
- CI and release workflows run the same `make test` command used locally.

### Fixed
- Gateway daemon startup now detaches reliably and verifies the gateway port is
  listening before reporting success.
- `pwt create --dry-run` now calls out that raw `git worktree add` skips pwt
  setup hooks, metadata, port allocation, and local project files.

## [0.1.11] - 2026-03-20

### Added
- **`pwt_arg` helper**: Extract flags from `PWT_ARGS` inside Pwtfiles
  - `pwt_arg -p` -> value, `pwt_arg --worker` -> `"true"`, `pwt_arg --port=5002` -> `"5002"`
  - Returns exit 1 when flag not found (use `|| true` for optional flags)
  - Works with `set -u` strict mode
- **Server on main app (`@`)**: `pwt server` now works from the main app directory
  - `pwt server @` explicitly targets main app from anywhere
  - Auto-detects main app when pwd is inside `$MAIN_APP`
  - Uses `BASE_PORT` (from Pwtfile `PORT_BASE`) for main app port

### Changed
- `cmd_server` flag parsing: flags with values (`-p 5002`) now correctly captured as pairs
- Current symlink pointing to `@` no longer errors; runs server on main app instead

### Internal
- Replaced `$(basename ...)` with `${var##*/}` parameter expansion in shell-init (faster, no fork)
- Replaced `basename "$(dirname ...)"` with `${var%/*}` chains in `_pwt_detect_project`

## [0.1.10] - 2026-02-05

### Added
- **Description in create**: `pwt create TICKET "auth login bug"` - quoted text with spaces is auto-detected as description
- **Meta shortcut**: `pwt meta <key> [value]` for quick get/set on current worktree
  - `pwt meta description` - get description
  - `pwt meta description "my task"` - set description
  - `pwt meta "text with spaces"` - shorthand for setting description
- **Description search in cd**: `pwt cd <term>` now searches both name and description
  - Supports multi-word search: `pwt cd "auth login"` finds "fixing auth login bug"
  - Case-insensitive partial matching
  - Single match navigates directly; multiple/zero matches → fzf fallback
- **Interactive query flag**: `pwt select --query <text>` to pre-filter fzf results
- **Short alias**: `pwt m` as alias for `pwt meta`
- **Background execution**: `--bg` flag to daemonize Pwtfile commands (e.g., `pwt server --bg`)
  - Uses perl double-fork + setsid for reliable process detachment
  - Outputs JSON with job_id, pid, and log file path
  - Duplicate job detection prevents running same command twice
- **Non-interactive mode**: `--no-input` flag closes stdin and sets `PWT_AGENT=1`
  - Designed for CI/CD and AI agent workflows
  - Prevents interactive prompts from blocking automated processes
- **Job management**: `pwt jobs` command to manage background jobs
  - `pwt jobs list` - show all running/stopped jobs
  - `pwt jobs logs <id> [-f]` - view/follow job output
  - `pwt jobs stop <id>` - stop a running job
  - `pwt jobs stop --all` - stop all jobs
  - `pwt jobs clean` - remove stale entries
- **PWT_AGENT variable**: Exported to Pwtfiles (defaults to `0`, set to `1` with `--no-input`)
- **Partial match in remove**: `pwt remove 12345` matches `TICKET-12345` automatically
  - Single match resolves directly; ambiguous matches show candidates and abort
- **Help for all commands**: Every command now supports `-h`/`--help`
  - Added help to: current, use, fix-port, select, steps, step, repair, port, open, alias
  - `pwt help <alias>` resolves aliases (add→create, rm→remove, ls→list, fix→repair, m→meta, s→server)

### Changed
- Comprehensive `pwt meta` help with ASCII diagrams showing where metadata appears
- Help text shows alias forms: `Usage: pwt create|add`, `pwt remove|rm`, `pwt list|ls`, etc.
- `@` (main app) documented consistently across info, editor, ai help texts
- Flag ordering standardized to `-short|--long` pattern (cmd_select)
- Trailing slash normalization added to cmd_run and cmd_open (shell completion compat)

### Fixed
- `pwt help <command>` now correctly dispatches to module commands (create, remove, list, etc.)

### Internal
- Extracted `get_worktree_port()` helper to deduplicate port lookup with legacy fallback
- New `lib/pwt/jobs.sh` module for background job state management
- `_strip_pwt_execution_flags()` helper strips --bg/--no-input from PWT_ARGS
- Fixed `cmd_server` dispatch to pass all args (was losing flags like --worker)

## [0.1.9] - 2026-02-03

### Added
- Quick demo video (GIF and MP4) in README

### Changed
- Updated README with demo-aligned command examples
- Simplified Everyday Commands table

### Removed
- Formula folder (moved to separate homebrew-pwt tap)
- Examples folder (replaced by main demo)

## [0.1.0] - 2026-02-02

### Added
- **Initial public release**
- **Core commands**: create, remove, list, cd, use, current, info
- **Worktree management**: Git worktrees with port allocation
- **Clone mode**: `--clone` flag for full isolation when needed
- **Pwtfile**: Project-local workflow file (setup/server/teardown)
- **Global Pwtfile**: `~/.pwt/Pwtfile` for shared commands across projects
- **Interactive selection**: `pwt select` and `pwt pick` with fzf
- **Interactive TUI**: `pwt status` command with htop-like dashboard
- **Shell integration**: `pwt shell-init` for bash/zsh/fish
- **Plugin system**: `pwt plugin install/remove/create`
- **Built-in plugins**: pwt-aitools, pwt-extras
- **Claude Code integration**: `pwt claude-setup` and `pwt ai` commands
- **Distribution**: Homebrew formula, npm package, and Makefile
- **Shell completions**: Bash, Fish, and Zsh completions
- **Man page**: Full manual page (`man pwt`)
- **Test suite**: 530+ tests with BATS framework
- **CI/CD**: GitHub Actions for automated testing

[Unreleased]: https://github.com/jonasporto/pwt/compare/v0.1.14...HEAD
[0.1.14]: https://github.com/jonasporto/pwt/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/jonasporto/pwt/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/jonasporto/pwt/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/jonasporto/pwt/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/jonasporto/pwt/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/jonasporto/pwt/compare/v0.1.0...v0.1.9
[0.1.0]: https://github.com/jonasporto/pwt/releases/tag/v0.1.0
