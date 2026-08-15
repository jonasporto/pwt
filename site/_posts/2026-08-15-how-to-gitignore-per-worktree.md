---
title: "How to gitignore per worktree"
description: "The .git/worktrees/<name>/info/exclude file every answer cites is never read by git. Here is the measurement, the method that actually works, and the two gotchas inside it."
featured: true
tags: [worktrees, env-config, cli]
agent_hint: false
---

You want a file ignored in one worktree only: not committed to
`.gitignore`, not ignored everywhere on your machine, just invisible in
this one checkout. Here is the version that actually works:

```bash
git config extensions.worktreeConfig true         # once per repo
git -C <worktree> config --worktree \
    core.excludesFile /abs/path/to/exclude-file   # once per worktree
echo "debug.log" >> /abs/path/to/exclude-file
```

The rest of this post is why the popular answers fail, measured, and the
two gotchas inside the working one. Everything below was run today on git
2.39.5.

## The file everyone cites is never read

Search for this and the top answers, including a dedicated guide site and
well-starred gists, tell you a linked worktree has its own exclude file at
`.git/worktrees/<name>/info/exclude`. It sounds right: that directory is
the worktree's private git dir, and `info/exclude` is where repo-local
ignores live. Measured:

```
$ echo "debug.log" > .git/worktrees/wt-a/info/exclude
$ touch wt-a/debug.log
$ git -C wt-a status --porcelain
?? debug.log
```

**Git does not read that path.** Ignore patterns come from
`$GIT_COMMON_DIR/info/exclude`, the directory all worktrees share, and git
never consults a per-worktree `info/` for excludes. The failure mode is
the worst kind: nothing errors, the file just sits there, and you believe
the pattern is active until an agent runs `git add -A` and commits the
thing you "ignored".

Two more non-answers, briefly. A different `.gitignore` per worktree does
not exist as a concept: `.gitignore` is tracked content, so it belongs to
the branch, follows every checkout of that branch, and any edit is one
`git add` away from being committed for the whole team. And the global
`core.excludesFile` is the opposite scope, every repo on the machine,
[which is its own trap]({{ '/blog/i-found-two-global-gitignores-on-my-machine/' | relative_url }}).

## The almost-right answer: one file for all worktrees

`.git/info/exclude` in the common directory works and is never committed.
Its scope surprises people in the other direction:

```
$ echo "debug.log" >> .git/info/exclude
$ git status --porcelain; git -C wt-a status --porcelain; git -C wt-b status --porcelain
(empty)  (empty)  (empty)
```

One line, ignored in the main checkout and in every worktree, current and
future. Before reaching for true per-worktree isolation, check whether
this is actually what you need: an ignore pattern for a file that does not
exist costs nothing, so the union of every worktree's patterns in one
shared file behaves identically to per-worktree files in almost every
real case. You need real per-worktree scope only when the same filename
must be ignored in one worktree and *visible* in another.

## True per-worktree: worktreeConfig

When you do need it, git has it, behind an extension:

```
$ git config extensions.worktreeConfig true
$ git -C wt-a config --worktree core.excludesFile \
      "$PWD/.git/worktrees/wt-a/info/exclude"
$ git -C wt-a status --porcelain    # debug.log ignored here
(empty)
$ git -C wt-b status --porcelain    # and only here
?? debug.log
```

A nice touch: pointing `core.excludesFile` at
`.git/worktrees/<name>/info/exclude` makes the internet's mythical file
real. Git still does not read it on its own; the `--worktree` config is
what wires it in, and the path is simply a sensible place to keep the
patterns, since it dies with the worktree.

Two gotchas cost me a retake each:

**The path must be absolute.** My first attempt used a relative path and
nothing was ignored, silently: a relative `core.excludesFile` resolves
against wherever the command runs, not against the git dir.

**Per-worktree `core.excludesFile` replaces the outer one.** The key is
single-valued, so the most specific scope wins alone; it does not stack:

```
-- repo-level excludesFile ignores *.tmp
-- wt-a sets a worktree-level excludesFile for debug.log
$ git -C wt-b status --porcelain | grep tmp    # still ignored
(empty)
$ git -C wt-a status --porcelain | grep tmp    # resurfaced
?? x.tmp
```

The worktree that customized its excludes lost every pattern from the
level above. If you use this, copy the outer patterns into the
per-worktree file, and remember the config is machine-local state: a new
clone, a teammate, a recreated worktree all start from zero.

## Declaring it once, in the repo

For the common case, the shared `info/exclude`, pwt can own the writing.
The project's `Pwtfile` (which *is* committed) declares the patterns, and
every `pwt create` applies them idempotently:

```bash
# Pwtfile
setup() {
    pwtfile_git_exclude "pnpm-lock.yaml" "pnpm-workspace.yaml" ".claude/"
}
```

`pwtfile_git_exclude` (pwt ≥ 0.2.2) appends each pattern to the common
`.git/info/exclude` only if it is not already there, so the declaration is
safe to run on every worktree creation, and a fresh machine converges the
first time it creates a worktree. The knowledge travels in the commit; the
ignore state stays out of it.

## You do not have to memorize any of this

The honest summary of this post is "git has four ignore layers, one famous
path is fake, one config key silently replaces another, and paths must be
absolute". Nobody should keep that in their head, and with an agent in the
loop, nobody has to. `pwt skill` prints the agent-facing guide to pwt,
including the Pwtfile helpers:

```
you> ignore the generated pnpm files in every worktree,
     without committing anything
agent> runs pwt skill, reads the guide, adds
       pwtfile_git_exclude "pnpm-lock.yaml" "pnpm-workspace.yaml"
       to setup(), creates a throwaway worktree, checks git status
```

Point the agent at the repo, state the outcome you want, and let it find
the mechanism in the guide. That is what the guide is for.

[pwt](https://github.com/jonasporto/pwt) is a git worktree manager for
parallel development: `brew install jonasporto/pwt/pwt`. The exclude
helper landed in v0.2.2, alongside the
[port allocation]({{ '/blog/how-to-deal-with-port-allocation-in-git-worktrees/' | relative_url }})
and [setup hooks]({{ '/blog/how-to-copy-env-into-a-git-worktree-and-what-it-breaks/' | relative_url }})
from earlier posts.
