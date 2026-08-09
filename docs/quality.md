# Code quality: tools, gates and baselines

Everything here is reproducible with one command:

```bash
scripts/check            # all stages
scripts/check fast       # sub-second subset (what pre-commit runs)
scripts/check lint       # linters only
scripts/check tests      # suite under both bash versions
scripts/check coverage   # kcov, best effort (see below)
```

Stages are split into **gates** (decide the exit code) and **informational**
(report a number). A stage only becomes a gate once its backlog is zero, so
the pipeline is never noisy enough to be ignored.

| Stage | Kind | Baseline (2026-08-09) |
|---|---|---|
| `bash -n` syntax | gate | clean |
| `shellcheck -x -S error` | gate | **0** |
| Docs consistency (man coverage, version match) | gate | clean |
| Test suite, bash 5.x | gate | 843 passing |
| Test suite, macOS system bash 3.2 | gate | 843 passing |
| Test suite under `set -u` (CI) | gate | passing |
| `shellcheck -S warning` | informational | 332 (301 of them SC2155) |
| `shfmt` | informational | 4 files unformatted |
| Coverage (kcov) | informational, Linux CI only | not yet reported |

## Why SC2155 is not "just fixed"

301 of the 332 warnings are SC2155 — `local x=$(cmd)` masking the command's
exit status. The mechanical fix is to split declaration from assignment, and
it is tempting because it would take the project to ~31 warnings and let the
gate move to `-S warning`.

**It was tried, and it broke 621 of 843 tests.** The reason is worth writing
down: in a script running `set -euo pipefail`, the mask is *load-bearing*.

```bash
local remote_head=$(git symbolic-ref refs/remotes/origin/HEAD)   # tolerated
remote_head=$(git symbolic-ref refs/remotes/origin/HEAD)         # aborts
```

`local` returns 0 regardless, so a command that legitimately fails — a repo
with no remote, an absent optional tool, a `grep` that finds nothing — leaves
the variable empty and execution continues. A plain assignment propagates the
failure and `set -e` kills the command. `detect_default_branch` was the first
of many.

So SC2155 here is not one defect repeated 301 times; it is 301 individual
questions of "may this command fail?". The honest options:

1. **Per-site review over time.** Correct, slow, and the only way to actually
   gain the safety SC2155 is about. Each site becomes either a split with
   explicit `|| true`, or a split that genuinely should abort.
2. **Differential linting** (rbenv/Bash-it pattern): gate only lines a PR
   touches, leaving the legacy backlog alone. Zero churn, and new code is
   held to the higher standard.
3. **Do not** add `disable=SC2155` to a `.shellcheckrc`: that suppresses
   future instances too, which is exactly what a backlog mechanism must not
   do.

Option 2 is the intended next step; option 1 happens opportunistically when a
function is being edited anyway.

## Formatting

`.editorconfig` is the single source of truth — shfmt reads it when given no
printer flags. **Passing any printer flag on the command line disables
EditorConfig entirely**, so `scripts/check` and the hooks call bare
`shfmt -l` / `shfmt -w`.

The remaining unformatted files are a pending one-shot reformat
(~2,300 lines). When it lands it should be a standalone commit, recorded in
`.git-blame-ignore-revs`, after which `check_format` becomes a gate.

## Test coverage

kcov works on Linux and **cannot work on macOS here**: below bash 4.2 kcov
falls back to stderr for its trace, and under bats, bats owns stderr. Since
`bin/pwt` is `#!/bin/bash` (3.2.57 on macOS), local coverage reports 0%.

Coverage therefore belongs in Linux CI, non-blocking, with kcov pinned from
its GitHub release — distro packages are unusable (Ubuntu 22.04 ships kcov 38,
which reports 0%; 24.04 does not package it at all).

Two structural ceilings worth knowing before chasing a number: tests that use
`source_pwt_function` (which `eval`s a `sed`-extracted function body) are
invisible to any line-coverage tool, and a coverage gate needs a test of its
own — the only comparable project in the ecosystem, bats-core, has a gate
that silently never fires because it compares against an undefined variable.

## Tools deliberately not used

- **bashate** — frozen upstream since 2022; its 166 `E042` findings duplicate
  SC2155 almost exactly, `E040` is literally `bash -n`, and `E020` matched
  nothing across 202 functions. Removed from the pipeline.
- **shellharden `--replace`** — would rewrite `for arg in $PWT_ARGS`, which
  depends on word splitting. Safe only as `--check`.
- **checkbashisms / `shfmt -ln posix`** — pwt targets bash deliberately.
- **shellspec** — upstream last released 2021, and its coverage feature does
  not instrument external commands, which is how every pwt test invokes the
  binary.

## Verification environments, and what only each one catches

| Environment | Only this one catches |
|---|---|
| macOS bash 5.x | assertions that bash 3.2 silently swallows mid-test |
| macOS system bash 3.2 | bash-4+ syntax leaking into code or test helpers |
| Linux CI | BSD-vs-GNU userland (`sed -i ''`, `stat` flags), inherited-fd hangs |
| Linux, `set -u` forced on | missing `${VAR:-}` defaults, including in the shell function pwt generates for the user's shell |
| Debian slim, no optional tools | the "core is bash + git + coreutils" promise |

The `set -u` job deserves special mention: it mechanically enforces the
`PWT_*` rule in CLAUDE.md, replacing one hand-written test per variable. On
its first run it found five real bugs in the generated shell function, which
had been shipping unguarded `$ZSH_VERSION`, `$PROMPT_COMMAND` and positional
parameters — breaking `eval "$(pwt shell-init)"` for anyone whose own shell
runs `set -u`.

Note it forces `set -u` only, not bats-core's `set -uo noclobber`: noclobber
breaks every `>` onto an existing file, which is that project's style choice
and not part of pwt's contract.

## Git hooks

`scripts/install-hooks` installs both, split by cost:

- **pre-commit** — sub-second, staged files only: syntax, `shellcheck -S
  error`, shfmt report.
- **pre-push** — the full `scripts/check`.

The suite takes ~2 minutes; putting that in pre-commit taxes small commits and
trains everyone to reach for `--no-verify`, which protects nothing.
