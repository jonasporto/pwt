---
title: "How to run a command in every git worktree"
description: "Git has submodule foreach but no worktree foreach, so everyone writes the loop by hand. I tested the four versions the internet suggests: two hide failures, one aborts halfway, one breaks on a space."
featured: true
tags: [worktrees, cli, bash]
agent_hint_extra: >-
  `for-each` is part of that guide: ask the agent to do something "in all
  worktrees" and it reaches for `pwt for-each` by default, including the
  aggregated failure report, instead of typing one of the loops above.
---

You have a handful of worktrees and one command to run in all of them:
the test suite, a `git status`, a dependency install. Git ships
`git submodule foreach` but never shipped `git worktree foreach`, so the
answer you will find is a hand-written loop. Here is the version that
actually behaves:

```bash
status=0
while read -r _ path; do
    (cd "$path" && ./scripts/test) || { echo "FAILED: $path" >&2; status=1; }
done < <(git worktree list --porcelain | grep "^worktree ")
exit $status
```

Every part of that is load-bearing, and the rest of this post is the
evidence: I built a scratch project with three worktrees, broke the test
in one of them, and ran the four loop variants the internet suggests.
Three of the four got it wrong, each differently.

## Variant 1: the pipe that reports and then lies

The most common answer pipes into `while read` and appends an `|| echo`:

```
$ git worktree list --porcelain | grep "^worktree " | while read -r _ path; do
    (cd "$path" && ./scripts/test) || echo "failed: $path"
  done
failed: .../wts/TICKET-1102
$ echo $?
0
```

It *tells* you TICKET-1102 failed and then **exits 0**. The pipe runs the
loop in a subshell, so nothing you record inside it survives, and the
pipeline's status is the loop's, which succeeded. In CI this is a green
build with a broken worktree. The fix is the process substitution in the
version up top: the loop runs in your shell, so `status=1` sticks.

## Variant 2: no error handling, with and without set -e

Drop the `||` entirely, which is how most one-off loops get typed:

- **Without `set -e`**: the failure vanishes. Loop exits 0, nothing
  printed, nothing recorded.
- **With `set -e`** (a script): the first failing worktree **aborts the
  whole sweep**. In my run, TICKET-1102 failed and TICKET-1103 was never
  visited. You do not learn whether the rest passes, which was the whole
  question.

Same loop, two shells, two different wrong answers.

## Variant 3: awk, until a path has a space

Plenty of answers skip `--porcelain` and parse the human output:

```
$ for path in $(git worktree list | awk '{print $1}'); do
    (cd "$path" && ./scripts/test) || echo "failed: $path"
  done
cd: .../wts/hotfix: No such file or directory
failed: .../wts/hotfix
```

The worktree is called `hotfix urgente`. Word splitting cut it at the
space and the loop visited a directory that does not exist. One honest
footnote: the `--porcelain` + `read -r _ path` form survives spaces,
because `read` puts the rest of the line in its last variable; it is the
unquoted `$( )` and awk forms that break. Paths with newlines need
`--porcelain -z`, at which point the loop stops fitting in a comment box.

## The entry nobody filters

`git worktree list` includes the **main checkout** as its first entry.
Every loop above ran the command there too. Sometimes that is what you
want; often it silently is not (the command mutates state you meant to
keep clean in main). Either way, the loop does not ask.

## What the loop looks like as a command

[pwt](https://github.com/jonasporto/pwt) ships the loop as
`pwt for-each`, with the failure handling the DIY versions kept getting
wrong. Same scratch project, same broken worktree:

```
$ pwt for-each ./scripts/test
=== @ (main) ===
=== TICKET-1101 ===
=== TICKET-1102 ===
=== TICKET-1103 ===
✗ Command failed in 1 of 4 worktrees: TICKET-1102
$ echo $?
1
```

Every worktree gets a labeled header, the main checkout runs first and
is explicitly marked `@`, the sweep continues past failures, and the
exit is non-zero with the failing worktrees named. Each worktree also
gets its `PWT_*` environment, so the command can use the things pwt
already knows:

```bash
pwt for-each 'curl -s localhost:$PWT_PORT/health'   # each worktree's own port
pwt for-each migrate                                # a Pwtfile function, per worktree
```

The second form is the quiet superpower: if `migrate` is a function in
your [Pwtfile]({{ '/blog/how-to-copy-env-into-a-git-worktree-and-what-it-breaks/' | relative_url }}),
`for-each` runs it with each worktree's port, branch and path filled in,
which is how "run the migration everywhere" stops needing any loop at
all.

Full disclosure, because this blog measures its own tool by the same
rules: until this week `pwt for-each` had variant 2's bug. It printed a
checkmark and exited 0 no matter what failed. Writing this post is what
exposed it; the fix (aggregate per-worktree exit codes, name the
failures, exit non-zero) shipped with tests that were first run against
the old binary to prove they caught it.

`brew install jonasporto/pwt/pwt`, and `pwt for-each` is there after a
`pwt init`. The loop at the top of this post remains correct if you
would rather own it yourself.
