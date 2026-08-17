---
title: "Your agent created the worktree. Now it does not run."
description: "Coding agents create worktrees themselves, and a fresh checkout has no .env, no dependencies and no port of its own. The hook that fixes it makes you take over worktree creation, which is the part worth reading before you wire anything."
featured: true
tags: [worktrees, agents, env-config, ports]
agent_hint_extra: >-
  If the worktree already exists when you arrive, `pwt adopt` is the
  command: it registers the checkout, allocates its port and runs the
  project's setup hook, without recreating anything.
agent_hint_doc: /docs/commands/#adopt
agent_hint_doc_label: "pwt adopt"
---

Every parallel-agent workflow ends at the same wall. The agent creates a
worktree, starts working, and the first command fails: no `.env`, no
`node_modules`, and a dev server that wants the port another worktree is
already using.

This is not a bug in any of those tools. `git worktree add` checks out
**tracked** files, and everything that makes a checkout runnable is
untracked on purpose. The difference from the usual version of this
problem is who created the checkout: **you did not**. Your agent did, so
the advice that starts with "when you create the worktree" does not
apply.

## What the tools give you, and where each stops

**`.worktreeinclude`** (Claude Code) copies gitignored files into the new
worktree. It is the smallest possible fix and it works for secrets that
are identical everywhere. It cannot *derive* anything: every worktree
gets the same file, so the same `PORT=3000` and the same
`DATABASE_URL`. Copy a port into three worktrees and two of them will not
start.

**The `WorktreeCreate` hook** (Claude Code, shipped since the feature
request that collected 29 reactions) does run your script when the agent
makes a worktree. It is the real answer, with one consequence the
feature request thread flagged immediately: your hook is expected to
**create the worktree itself** and print the path. You are not adding
setup to Claude's worktree handling; you are replacing it.

That is fine if you have something that already knows how to create a
worktree properly. It is a lot to write from scratch.

**Nothing at all** is what you get from every other path: a teammate's
`git worktree add`, another agent tool, `claude-squad` (whose own issue
for this is still open), or the worktree you made by hand last Tuesday.

## Measured: what an agent-created worktree is missing

Three worktrees, created the way an agent creates them:

```
$ git worktree add ../wts/fix-login    -b fix-login
$ git worktree add ../wts/add-search   -b add-search
$ git worktree add ../wts/refactor-api -b refactor-api

fix-login:     .env MISSING
add-search:    .env MISSING
refactor-api:  .env MISSING
```

Copying `.env` into each would fix the first failure and create the next
one, because all three would then hold `PORT=3000`.

## Adopting what already exists

`pwt adopt` registers a checkout that someone else created: it allocates
a port, writes the metadata, and runs the project's `setup()` hook with
`$PWT_PORT` bound. From inside the worktree:

```
$ pwt adopt
Adopting worktree: agent-feature
  Branch: agent-feature
  Port:   4001

  ✓ Metadata saved
Running Pwtfile (setup)...
  ✓ Copied: .env
  ✓ Pwtfile (setup) completed

$ cat .env
PORT=4001
API_KEY=abc
```

The copy came from the hook; the **4001 did not**. The setup rewrote it
from the port pwt had just allocated, which is the difference between
copying config and deriving it.

For the pile that accumulated while you were not looking, `--all` takes
the whole directory:

```
$ pwt adopt --all
Adopting: add-search
Adopting: fix-login
Adopting: refactor-api
Adopted: 3  Skipped (already registered): 0  Failed: 0

fix-login      -> PORT=3002
add-search     -> PORT=3001
refactor-api   -> PORT=3003
```

Three worktrees, three ports, one command, and the ones already
registered are skipped rather than redone.

## If you do want the hook

The `WorktreeCreate` contract wants a script that creates the worktree
and prints its path. That is two lines when something else owns the
creation:

```bash
#!/usr/bin/env bash
# WorktreeCreate hook: pwt creates it (branch, port, setup), we print the path
name="${1:-agent-$(date +%s)}"
pwt --no-input create "$name" >/dev/null
pwt info "$name" --porcelain | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])'
```

`--no-input` matters: it closes stdin and sets `PWT_AGENT=1`, so a setup
hook that would have asked something fails instead of hanging a session
nobody is watching.

Worth being honest about the split: the hook covers the worktrees *that
agent* creates. `adopt` covers all the others, and there are always
others. They are not alternatives; the hook is the front door and
`adopt` is the one you use for everything that came in through a window.

## The rule underneath

A worktree is not ready because it exists. It is ready when the values
that must differ per worktree have been derived rather than copied:
the port, the database name, whatever your stack keys on. Which tool
created the directory is an implementation detail, and any workflow that
only works when *you* created it will break the first time an agent gets
there first.

`brew install jonasporto/pwt/pwt`, then `pwt adopt` inside the worktree
your agent already made
([reference]({{ '/docs/commands/#adopt' | relative_url }})). What
`setup()` should do with the port, the database and the dependency store
is [its own post]({{ '/blog/how-to-copy-env-into-a-git-worktree-and-what-it-breaks/' | relative_url }}).
