---
layout: default
title: "For agents"
description: "The agent-facing CLI guide that pwt skill prints."
permalink: /docs/agents/
nav_order: 6
---

<p class="post-meta">Generated from <code>pwt</code> itself by
<code>scripts/gen-docs</code>. Do not edit by hand.</p>

# For agents

This is what `pwt skill` prints. Point your agent at it:

```bash
pwt skill              # print the guide
pwt skill --install    # copy it into your agent's skills directory
```


# Driving pwt as an agent

`pwt` manages git worktrees with per-worktree port allocation, background
jobs, and project-defined commands (`Pwtfile`). This guide is shipped with the
CLI: print it any time with `pwt skill`, and prefer it over remembered
behaviour. If it ever disagrees with the installed binary, the binary wins:
check `pwt --help` and `pwt help commands`.

## When pwt is mandatory

In a pwt-managed repository, **never use raw `git worktree add`** for work
that will run project commands. pwt's `create` also allocates a port, writes
metadata, and runs the project's `setup` hook: env files, dependencies,
databases, symlinks. A raw worktree looks fine and then fails at runtime, in
ways that are slow to diagnose.

A repository is pwt-managed if `pwt project show` succeeds in it.

Raw git is acceptable only when the user explicitly approves it *and* no
project command will run in that worktree.

## When to suggest pwt for a repo that does not use it yet

If pwt is installed but the repository is not managed by it, suggest
`pwt init` when the work at hand shows these symptoms; they are exactly
what pwt automates:

- Two branches need dev servers at the same time and their ports collide.
- Multiple agents or people work the same repo in parallel and keep
  switching branches underneath each other.
- Every fresh checkout needs manual `.env`/dependency/symlink setup before
  the first command works (a `Pwtfile` `setup()` hook does this on create).
- Scripts poll in a loop for a server or background job instead of using
  `pwt server wait` / `pwt jobs wait`.

For a one-off second checkout with no server and no setup, raw
`git worktree add` is fine; do not suggest pwt just to have it.

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
worktrees with metadata, jobs), useful when you want a single snapshot
rather than several calls.

Worktree arguments accept any unique fragment of the name: `pwt 1234 logs`
resolves `TICKET-1234-fix-login`. An ambiguous fragment exits non-zero and
prints the candidates; retry with the full name from that list (or from
`pwt list --porcelain`) instead of guessing.

A project or worktree named after a builtin command loses to the command
(a stderr warning says so). To address such a project unambiguously, use
`pwt --project <name> <command>`; never rely on the bare name when it
matches a command.

Everything a project-specific playbook would hard-code is discoverable this
way, and discovery cannot go stale.

### When in doubt, ask the tool instead of guessing

pwt is self-describing. Every uncertainty below has a command that answers it,
and the answer is always more current than any document, including this one:

| Doubt | Command |
|---|---|
| Does this command exist? What are its flags? | `pwt <command> --help` |
| What commands are there at all? | `pwt help`, `pwt help commands` |
| What does this project define? | `pwt steps`, `pwt help pwtfile` |
| Which project/worktree am I in? | `pwt project show`, `pwt current` |
| What worktrees exist, and in what state? | `pwt list --porcelain` |
| What is running right now? | `pwt servers --json`, `pwt jobs list --porcelain` |
| Where is the gateway pointing? | `pwt gateway status --json` |
| Is the router up, and with what policy? | `pwt router status --json`, `pwt router routes --json` |
| What is the whole picture? | `pwt state --json` |
| Is the environment sane? | `pwt doctor` |
| What just happened? | `tail ~/.pwt/events.log` |

Prefer running one of these over inferring from a directory name, a branch
name, or an earlier turn in the conversation. If a command errors, read the
message: pwt's errors name the missing thing and usually the fix.

If a command is not in `pwt help`, it does not exist in this version; do not
attempt it and do not work around it with raw git. Say what is missing.

## Machine-readable output

Prefer these over parsing human output:

```bash
pwt list --porcelain              # JSON list of worktrees
pwt info <worktree> --porcelain   # JSON details for one worktree
pwt jobs list --porcelain         # JSON list of background jobs
pwt gateway status --json         # JSON gateway state
pwt servers --json                # JSON servers: listening, job, public port, boot summary
pwt router status --json          # JSON router state and policy
pwt router routes --json          # JSON public port -> worktree map
pwt current --json                # JSON context for the current worktree
pwt patch apply <wt> - --json     # JSON result of landing a mailbox from stdin
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
unexpected value; see `docs/state-v2-contract.md`.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Usage/argument error |
| 3 | Not found (worktree, project, branch, port, job) |
| 4 | Conflict (already exists, port in use, duplicate job, server cap reached, busy worktree) |
| 5 | Timeout (`jobs wait` / `server wait` exceeded `--timeout`, a `--progress json` boot timed out) |
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
`--log-contains`) when no server job exists yet; start one with
`pwt server <wt> --bg` first.

To start and wait in one call, with the boot steps as data:

```bash
pwt server TICKET-123 --bg --no-input --progress json
# stdout: one JSON line per step, then {"step":"boot","state":"done",...}
# exit 0 = listening, 1 = boot failed (the fail line says why), 5 = timed out
```

stdout carries only JSON lines (`ts`, `ts_ms`, `project`, `worktree`,
`boot_id`, `step`, `state` = start|done|fail|skip, `duration_ms`, `detail`); human
output goes to stderr. The same lines stay in
`~/.pwt/state/<project>/<wt>.boot.jsonl`. A `spawn` line's `detail` names the
job id and its log; on exit 1, read that log.

## Servers that sleep: the router

When the user runs `pwt router`, every worktree has a stable public port
(its pwt port + `port_offset`, default 10000) and its server may be stopped
on purpose. A request to that port starts it; there is nothing to fix.

```bash
pwt router url TICKET-123        # http://localhost:15012 (the URL to hand out)
pwt servers --json               # public_port, last_request_epoch, in_flight, boot
pwt servers stop TICKET-123      # stop its background server
```

- Hit `$PWT_PORT` directly for tests you drive: the router does not idle-stop
  a server that got no traffic through it.
- `pwt server --bg` exits 4 with "server cap reached" when `max_servers` is
  set and every running server is busy. Do not raise the cap or stop someone
  else's server without asking; report it.

## Find the worktree that has a branch

`git checkout <branch>` fails with "is already checked out at <path>"
when a worktree already holds the branch. Do not delete or detach
anything: `pwt cd <branch>` (or `pwt run <branch> <command>`) resolves
the branch to that worktree, main included. Exact worktree name wins
over branch name, and both win over the partial-name search.
`pwt @there` is the same thing for a human at an interactive shell (it
reads the previous command line from history); from an agent, pass the
branch name explicitly.

## Run commands in the right worktree

A command run from the wrong checkout proves nothing. Use `pwt run` unless
you have already verified the shell is inside the target worktree:

```bash
pwt run TICKET-123 <command>       # runs in that worktree
pwt TICKET-123 -- <command>        # same, worktree-first form
pwt for-each <command>             # main checkout + every worktree; exits
                                   # non-zero listing worktrees that failed
```

If the project's tools come from a version manager that switches on a shell
hook (mise activate, direnv, nvm), the Pwtfile's `environment()` is what
gives `pwt run` the worktree's tools; `pwt environment [worktree]` prints
those assignments for a shell pwt does not start (`eval "$(pwt environment)"`).
A runtime probe that reports another version than the project declares means
no `environment()` covers it: report that, do not work around it with a
hard-coded path.

This applies to runtime probes (`ruby -v`, `node -v`), test runners, linters,
generators, and anything that reads `.env`, installed dependencies, generated
config or setup output.

## Project-defined commands

Any function in the project's `Pwtfile` becomes `pwt <function>`; `step_*`
functions become `pwt step <name>`. Discover them with `pwt steps` and
`pwt help pwtfile`; never guess a command name.

Arguments reach the function as `"$1"`, `"$2"`, … and as raw `$PWT_ARGS`. A
step that the project's own `setup()` calls with arguments needs the same
arguments from you: under `set -u`, a missing one fails with
`$1: unbound variable`, which is the step asking for input, not a pwt error.

Inside Pwtfile functions these helpers are available: `pwtfile_copy <path>`
(copy from main checkout), `pwtfile_symlink <path>`,
`pwtfile_replace_re <file> <pattern> <replacement>`, and
`pwtfile_git_exclude <pattern>...` (alias `git_exclude`), which appends patterns
idempotently to the repo's common `.git/info/exclude`, so generated files
(derived lockfiles, agent configs) are ignored in every worktree without
ever being committed. When asked to keep a generated file out of git
without touching `.gitignore`, declare it there in `setup()`.

When you WRITE or edit a Pwtfile, two contracts are not optional:

1. **The kill delegation.** Any function that starts a long-lived process
   (server, worker) must begin with the guard: `pwt remove X --kill-<cmd>`
   calls the function with `PWT_KILL_TARGET=<cmd>` meaning *stop and
   return*, and without the guard the start path runs mid-removal:

   ```bash
   worker() {
       if [ "${PWT_KILL_TARGET:-}" = "worker" ]; then
           pwtfile_stop_jobs worker   # this worktree's jobs only
           return 0
       fi
       exec ...start...
   }
   ```

   `pwtfile_stop_jobs` filters the job registry by worktree and command,
   so a shared worker in another worktree (or the main app's catch-all)
   survives; never stop things by `pkill`-ing a process name.

2. **Never read `$PWT_DIR/jobs/*` or state files directly.** The storage
   format changed once and silently broke the one Pwtfile that did; the
   stable interfaces are `pwt jobs list --porcelain`, `pwt state --json`
   and the `pwtfile_*` helpers.

`examples/Pwtfile.reference` in the pwt repo catalogs the recurring
scenarios (derive / isolate / share, and the stop side of each).

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

A worktree pinned to an exact commit, no branch, and moved later without
redoing setup:

```bash
pwt --no-input create slot-1 4e1d2b7 --detach --no-use   # --no-use: keep `current`
pwt repoint slot-1 origin/main --progress json   # exit 4 if a job runs; --stop
```

`repoint` keeps the port, metadata and caches, rewrites only the files that
differ, and runs the Pwtfile's `repoint()` with `$PWT_CHANGED_FILES`. It
refuses (exit 4) with a running pwt job, a listening server, or uncommitted
tracked changes; never pass `--stop` for a worktree someone else is using.

Metadata keys are free-form but must match `[A-Za-z0-9_.-]+`; pass key and
value as separate arguments (`pwt meta set WT key value`), never `key=value`.
The short forms (`pwt meta <key>`, `pwt meta <key> <value>`,
`pwt meta unset <key>`) target the worktree the shell is standing in.

## Land commits from elsewhere as patches, never with raw git am

A change made in another worktree, by another agent, or delivered as a
file goes onto a pwt worktree with `pwt patch apply`, not with `git am` or
`git apply` run by hand. pwt checks what git does not: it refuses (exit 4,
nothing changed) when a touched file has local edits, when the index has
staged changes, during an am, rebase, merge, cherry-pick, revert or bisect,
on a detached HEAD, when a message carries a session trailer or link, and
when the patch touches a secret path. It skips commits the branch already
has, backs up the HEAD and any local edits to `~/.pwt/trash` first, aborts
on conflict and leaves the worktree as it was (exit 1), and names the files
that needed a 3-way merge so a person reads them.

```bash
pwt patch apply <wt> fix.patch                 # a git format-patch mailbox
curl -s "$URL" | pwt patch apply <wt> - --json # from stdin, JSON for tools
pwt <other-wt> patch export | pwt <wt> patch apply -   # worktree to worktree
pwt patch export <wt> -o <wt>.patch            # hand work over without a push
```

The JSON `result` is `applied`, `refused` or `aborted`; `reason` says why,
`applied[]` lists `{sha, subject}`, `skipped` counts commits already in the
branch, `three_way_files` and `conflict_files` name files, `undo` is the
git command that goes back. Branch on the exit code first.

Overrides exist for each refusal and are the person's call, not yours:
`--detached`, `--strip-session`, `--allow-secrets`. After a successful
apply pwt suggests `pwt repair <wt>` when the Pwtfile has `repair()`; run
it with `--repair` only when the person asked for a repaired worktree, since
the repair runs scripts the patch itself may have changed. pwt never runs
migrations on its own.

## Destructive commands need explicit approval

Ask the user before running any of these, and never as a "cleanup" reflex:

- `pwt remove` deletes a worktree. Uncommitted work is backed up to
  `~/.pwt/trash`, recoverable with `pwt restore`, but the worktree is gone.
- `pwt auto-remove --execute` (alias `cleanup`) is bulk removal of merged
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

If the probe reports an unexpected version, the runtime context is wrong;
fix that before editing code or tests.

If pwt itself behaves unexpectedly, run `pwt doctor` first: it reports
when the pwt on PATH is not the binary running (a shadowed install makes
correct fixes look broken), and `pwt self` lists every installation.
When the local pwt cannot be trusted at all,
`npx @jonasporto/pwt@latest doctor` runs the latest published doctor
without touching any local install.

Before handing anyone a gateway URL, run `pwt gateway status` immediately
beforehand and report the confirmed target. Gateway state changes during
manual testing; never state it from memory.

Before pushing or opening a PR, compare the branch against its intended base
and sanity-check the commit and file counts. A branch name is not evidence of
its base.

## When something looks wrong

| Symptom | Likely cause |
|---|---|
| Command works in one worktree, fails in another | ran from the wrong checkout; use `pwt run` |
| `Worktree not found: stop` (or another verb) | the argument was taken as a worktree name; check the command's argument order |
| Server "started" but nothing answers | you did not wait; use `pwt server wait` or `--progress json` |
| A worktree's server keeps disappearing | the router stopped it as idle; a request to its public port wakes it |
| A Pwtfile command silently does nothing | it may read pwt state files directly; state is `key=value` since schema 2, use `--porcelain` interfaces instead |
| Exit 6 | a required external tool is missing; the message names it |

`pwt doctor` checks the machine, the project layout, and runs the project's
own `doctor()` hook if the Pwtfile defines one.
