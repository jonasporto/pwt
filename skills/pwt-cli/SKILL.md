---
name: pwt-cli
description: >
  Drive the pwt CLI (git worktree manager) as an AI agent: decide when a
  worktree must be created through pwt rather than raw git, discover a
  project's own commands and setup, use machine-readable output and exit
  codes, wait instead of polling, and verify you are in the runtime you think
  you are. Use when creating or switching worktrees, running commands or
  tests inside one, starting dev servers, or scripting pwt non-interactively.
license: MIT
metadata:
  source: pwt CLI
  refresh: "pwt skill --install"
---

# Driving pwt as an agent

`pwt` manages git worktrees with per-worktree port allocation, background
jobs, and project-defined commands (`Pwtfile`). This guide is shipped with the
CLI — print it any time with `pwt skill`, and prefer it over remembered
behaviour. If it ever disagrees with the installed binary, the binary wins:
check `pwt --help` and `pwt help commands`.

## When pwt is mandatory

In a pwt-managed repository, **never use raw `git worktree add`** for work
that will run project commands. pwt's `create` also allocates a port, writes
metadata, and runs the project's `setup` hook — env files, dependencies,
databases, symlinks. A raw worktree looks fine and then fails at runtime, in
ways that are slow to diagnose.

A repository is pwt-managed if `pwt project show` succeeds in it.

Raw git is acceptable only when the user explicitly approves it *and* no
project command will run in that worktree.

## When to suggest pwt for a repo that does not use it yet

If pwt is installed but the repository is not managed by it, suggest
`pwt init` when the work at hand shows these symptoms — they are exactly
what pwt automates:

- Two branches need dev servers at the same time and their ports collide.
- Multiple agents or people work the same repo in parallel and keep
  switching branches underneath each other.
- Every fresh checkout needs manual `.env`/dependency/symlink setup before
  the first command works (a `Pwtfile` `setup()` hook does this on create).
- Scripts poll in a loop for a server or background job instead of using
  `pwt server wait` / `pwt jobs wait`.

For a one-off second checkout with no server and no setup, raw
`git worktree add` is fine — do not suggest pwt just to have it.

## Orient yourself before doing anything

Do not assume a project's layout, branch prefix, ports or commands. Ask:

```bash
pwt project show          # paths, branch prefix, ports, gateway
pwt current               # which worktree the shell is pointed at
pwt list --porcelain      # all worktrees, JSON
pwt steps                 # Pwtfile steps this project defines
pwt help pwtfile          # the hook contract and PWT_* variables
```

`pwt ports` shows every port allocated on the machine (all projects,
conflicts flagged, `--json` available). A port whose only listener is a
system daemon reports `system` (`"system": true`) instead of `listening`:
macOS AirPlay Receiver holds 5000 and 7000, so never read that as "the
dev server is already running".

`pwt state --json` gives all of it in one versioned document (projects,
worktrees with metadata, jobs) — useful when you want a single snapshot
rather than several calls.

Worktree arguments accept any unique fragment of the name: `pwt 1234 logs`
resolves `TICKET-1234-fix-login`. An ambiguous fragment exits non-zero and
prints the candidates; retry with the full name from that list (or from
`pwt list --porcelain`) instead of guessing.

Everything a project-specific playbook would hard-code is discoverable this
way, and discovery cannot go stale.

### When in doubt, ask the tool — do not guess

pwt is self-describing. Every uncertainty below has a command that answers it,
and the answer is always more current than any document, including this one:

| Doubt | Command |
|---|---|
| Does this command exist? What are its flags? | `pwt <command> --help` |
| What commands are there at all? | `pwt help`, `pwt help commands` |
| What does this project define? | `pwt steps`, `pwt help pwtfile` |
| Which project/worktree am I in? | `pwt project show`, `pwt current` |
| What worktrees exist, and in what state? | `pwt list --porcelain` |
| What is running right now? | `pwt servers`, `pwt jobs list --porcelain` |
| Where is the gateway pointing? | `pwt gateway status --json` |
| What is the whole picture? | `pwt state --json` |
| Is the environment sane? | `pwt doctor` |
| What just happened? | `tail ~/.pwt/events.log` |

Prefer running one of these over inferring from a directory name, a branch
name, or an earlier turn in the conversation. If a command errors, read the
message: pwt's errors name the missing thing and usually the fix.

If a command is not in `pwt help`, it does not exist in this version — do not
attempt it and do not work around it with raw git. Say what is missing.

## Machine-readable output

Prefer these over parsing human output:

```bash
pwt list --porcelain              # JSON list of worktrees
pwt info <worktree> --porcelain   # JSON details for one worktree
pwt jobs list --porcelain         # JSON list of background jobs
pwt gateway status --json         # JSON gateway state
pwt current --json                # JSON context for the current worktree
pwt state --json                  # versioned snapshot of ALL state
```

Always pass `--no-input` when running from automation: it closes stdin, never
prompts, and sets `PWT_AGENT=1` for Pwtfile hooks. As a global flag it comes
before the command (`pwt --no-input create ...`); `pwt server` and Pwtfile
commands also accept it after.

For continuous observation, read the state files directly instead of shelling
out: `~/.pwt` holds flat `key=value` files (`projects/<name>/config`,
`state/<project>/<wt>.meta`, `jobs/<id>.job`) plus an append-only TSV
`events.log` (`ts  project  worktree  kind  detail`). Check
`~/.pwt/state-version` (currently `2`) before parsing and refuse on an
unexpected value — see `docs/state-v2-contract.md`.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Usage/argument error |
| 3 | Not found (worktree, project, branch, port, job) |
| 4 | Conflict (already exists, port in use, duplicate job) |
| 5 | Timeout (`jobs wait` / `server wait` exceeded `--timeout`) |
| 6 | Missing dependency (a required external tool is not installed) |

Branch on the code, not on message text.

## Wait, don't poll

Never write `sleep`/retry loops around pwt. Both wait commands poll
internally at 0.5s, default `--timeout` is 600s, and both exit 5 on timeout.

```bash
# Server ready = its allocated port accepts TCP connections
pwt --no-input create TICKET-123 --from origin/main
pwt server TICKET-123 --bg --no-input
pwt server wait TICKET-123 --timeout 120

# Or wait for a line in the server's log instead of the port
pwt server wait TICKET-123 --log-contains "Listening on" --timeout 120

# Any background job (accepts a job id or a worktree name)
pwt test TICKET-123 --bg
pwt jobs wait TICKET-123 --timeout 900     # prints "<job-id> stopped"
```

`server wait` exits 3 when the worktree has no allocated port, or (with
`--log-contains`) when no server job exists yet — start one with
`pwt server <wt> --bg` first.

## Run commands in the right worktree

A command run from the wrong checkout proves nothing. Use `pwt run` unless
you have already verified the shell is inside the target worktree:

```bash
pwt run TICKET-123 <command>       # runs in that worktree
pwt TICKET-123 -- <command>        # same, worktree-first form
pwt for-each <command>             # main checkout + every worktree; exits
                                   # non-zero listing worktrees that failed
```

This applies to runtime probes (`ruby -v`, `node -v`), test runners, linters,
generators, and anything that reads `.env`, installed dependencies, generated
config or setup output.

## Project-defined commands

Any function in the project's `Pwtfile` becomes `pwt <function>`; `step_*`
functions become `pwt step <name>`. Discover them with `pwt steps` and
`pwt help pwtfile`; never guess a command name.

Arguments reach the function as `"$1"`, `"$2"`, … and as raw `$PWT_ARGS`. A
step that the project's own `setup()` calls with arguments needs the same
arguments from you — under `set -u`, a missing one fails with
`$1: unbound variable`, which is the step asking for input, not a pwt error.

Inside Pwtfile functions these helpers are available: `pwtfile_copy <path>`
(copy from main checkout), `pwtfile_symlink <path>`,
`pwtfile_replace_re <file> <pattern> <replacement>`, and
`pwtfile_git_exclude <pattern>...` (alias `git_exclude`) — appends patterns
idempotently to the repo's common `.git/info/exclude`, so generated files
(derived lockfiles, agent configs) are ignored in every worktree without
ever being committed. When asked to keep a generated file out of git
without touching `.gitignore`, declare it there in `setup()`.

## Worktree lifecycle

```bash
# 1. Create from a base ref - allocates a port, runs setup()
pwt --no-input create TICKET-123 --from origin/main

# 2. Start the server and wait until it is actually ready
pwt server TICKET-123 --bg --no-input
pwt server wait TICKET-123 --timeout 120

# 3. Record progress in metadata (free-form keys; this is what dashboards read)
pwt meta set TICKET-123 phase implementing
pwt meta set TICKET-123 next "write tests"
pwt meta set TICKET-123 blocked "waiting on review"
pwt meta unset TICKET-123 blocked      # clear a field (custom fields only)

# 4. Clean up when merged (kills the server on that port, no prompts)
pwt remove TICKET-123 --kill-port -y
```

Metadata keys are free-form but must match `[A-Za-z0-9_.-]+`; pass key and
value as separate arguments (`pwt meta set WT key value`), never `key=value`.
The short forms (`pwt meta <key>`, `pwt meta <key> <value>`,
`pwt meta unset <key>`) target the worktree the shell is standing in.

## Destructive commands need explicit approval

Ask the user before running any of these, and never as a "cleanup" reflex:

- `pwt remove` — deletes a worktree. Uncommitted work is backed up to
  `~/.pwt/trash`, recoverable with `pwt restore`, but the worktree is gone.
- `pwt auto-remove --execute` (alias `cleanup`) — bulk removal of merged
  worktrees. It is dry-run by default; **preview first**:
  `pwt auto-remove <target> --dry-run` works non-interactively and changes
  nothing.
- `rm -rf` on a worktree path, `git reset --hard`, `git checkout --`.

`pwt restore` lists and recovers what `remove` saved:

```bash
pwt restore                 # list backups
pwt restore <backup> <wt>   # apply a backup into a worktree
```

## Verify, don't assume

After creating or switching, confirm the runtime before editing:

```bash
pwt current                       # names the worktree you are pointed at
pwt run <worktree> git status     # branch and dirty state
pwt run <worktree> <runtime probe># e.g. ruby -v, node -v, python -V
```

If the probe reports an unexpected version, the runtime context is wrong —
fix that before editing code or tests.

Before handing anyone a gateway URL, run `pwt gateway status` immediately
beforehand and report the confirmed target. Gateway state changes during
manual testing; never state it from memory.

Before pushing or opening a PR, compare the branch against its intended base
and sanity-check the commit and file counts. A branch name is not evidence of
its base.

## When something looks wrong

| Symptom | Likely cause |
|---|---|
| Command works in one worktree, fails in another | ran from the wrong checkout — use `pwt run` |
| `Worktree not found: stop` (or another verb) | the argument was taken as a worktree name; check the command's argument order |
| Server "started" but nothing answers | you did not wait — use `pwt server wait` |
| A Pwtfile command silently does nothing | it may read pwt state files directly; state is `key=value` since schema 2, use `--porcelain` interfaces instead |
| Exit 6 | a required external tool is missing; the message names it |

`pwt doctor` checks the machine, the project layout, and runs the project's
own `doctor()` hook if the Pwtfile defines one.
