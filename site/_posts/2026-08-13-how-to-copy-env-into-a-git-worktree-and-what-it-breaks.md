---
title: "How to copy .env into a git worktree, and what it breaks"
description: "Copying untracked config into a new worktree is the standard answer. Three worktrees later, two servers will not start and one branch is corrupting another's database."
featured: true
tags: [env-config, worktrees, ports]
---

You created a worktree, the app will not start, and `.env` is missing. Here
is the answer you came for:

```bash
# from the main checkout: every ignored file that actually exists
git ls-files --others --ignored --exclude-standard --directory
```

That prints the untracked files git deliberately left behind. Copy them into
the new worktree and the app starts.

Now the part nobody writes down: **do that for three worktrees and two of
them will not start, and one branch will silently corrupt another branch's
database.** Both are measured below, and the fix is not a better copy script.

## Why it happens at all

`git worktree add` checks out **tracked** files. Everything that makes a
checkout runnable is untracked by design: `.env` is gitignored because it
holds secrets, `node_modules` because it is derived. So a new worktree is
born unrunnable, and that is not a bug.

The demand for a fix is easy to see. There are open issues asking for a
worktree setup hook on
[Claude Code](https://github.com/anthropics/claude-code/issues/27744) (29
reactions) and again for
[hooks not firing](https://github.com/anthropics/claude-code/issues/29716)
(24 reactions), the same request on
[claude-squad](https://github.com/smtg-ai/claude-squad/issues/260), and at
least five published tools whose entire purpose is copying one file:
[copy-env](https://github.com/therohitdas/copy-env),
[copy-configs](https://github.com/gapurov/copy-configs),
[claude-worktree-hooks](https://github.com/tfriedel/claude-worktree-hooks),
[portree](https://github.com/fairy-pitta/portree),
[worktree-devservers](https://github.com/viktormarinho/worktree-devservers).
Claude Code even invented a `.worktreeinclude` file for it, which
[by its own documentation](https://wmedia.es/en/tips/claude-code-worktreeinclude-env-worktrees)
only copies: it cannot create a file and cannot derive a value.

Every one of those answers stops at copying. Here is what happens next.

## Measurement 1: two of three servers do not start

A throwaway project whose only feature is reading `PORT` and `DATABASE_URL`
from `.env`. Three worktrees, `.env` copied into each with the command above:

```
-- .env now identical in all four:
   distinct checksums: 1
-- start the app in each worktree:
   wt-a: DEAD -> OSError: [Errno 48] Address already in use
   wt-b: DEAD -> OSError: [Errno 48] Address already in use
   wt-c: up on 3000
```

Which one wins is a race. The copy was faithful, which is exactly the
problem: `PORT=3000` was correct in the main checkout and is wrong in every
copy of it.

This one is loud. You get an error, you understand it, you fix it by hand,
and you learn nothing. The next one is quiet.

## Measurement 2: one branch breaks another, with no error

The same copied `.env` carries `DATABASE_URL`. All three worktrees now point
at one database.

Branch A ships a migration. It is an ordinary one, a column rename:

```bash
alter table items rename column name to title;
```

Nobody touches branch B. No checkout, no pull, no edit. Branch B was green a
second ago:

```
-- branch B is green:
     1|one
     2|two
-- branch A ships a rename; nobody touches branch B:
     applied on feature-a
-- branch B now, with an unchanged working tree:
     Error: in prepare, no such column: name
     files changed in wt-b: 0
```

**Zero files changed in branch B, and branch B is broken.** Its code is
correct for its own schema. The database underneath it belongs to somebody
else's branch now.

This is the failure that copying causes rather than prevents, and it is the
one that eats an afternoon, because everything you look at in branch B is
fine. With parallel agents it gets worse: nobody was even watching when the
migration ran.

## The question copying cannot answer

The reason a copy is not enough is that `.env` is not one kind of thing. It
is a bag of values with three different requirements, and copying applies one
strategy to all of them.

For every global resource, with N worktrees, there are only three answers:

| Strategy | When | Examples |
|---|---|---|
| **Derive** | cheap, unique per worktree, needs no coordination | ports, database name suffixes, container names |
| **Isolate** | correctness requires separation | databases, queues, upload dirs |
| **Share** | expensive to build, identical across worktrees | package caches, dependency stores |

Copying is only correct for the fourth category nobody lists: values that are
genuinely identical everywhere, like an API key for a shared sandbox.

Read the two measurements again through this table. The port needed
**derive** and got copy, so it collided. The database needed **isolate** and
got copy, so it was shared. Dependencies, which are the expensive ones,
usually need **share**, and there
[a copy is the wrong answer for the opposite reason]({{ '/blog/sixty-three-worktrees-one-node-modules-problem/' | relative_url }}).

Getting this classification wrong is the whole of "works in one worktree,
breaks in another".

## What it looks like implemented

A setup hook that runs once when the worktree is created. This is the exact
file used for the measurements below, no elisions:

```bash
#!/bin/bash
PORT_BASE=3000

# Where this project keeps its databases: one level above the worktrees dir.
DATA_DIR="$(dirname "$(dirname "$PWT_WORKTREE_PATH")")/data"

setup() {
    pwtfile_copy ".env"

    # DERIVE: cheap, unique per worktree, needs no coordination
    pwtfile_replace_re ".env" "PORT=.*" "PORT=${PWT_PORT}"

    # ISOLATE: correctness requires separation
    local db="${DATA_DIR}/myapp_wt${PWT_PORT}.sqlite3"
    pwtfile_replace_re ".env" "DATABASE_URL=.*" "DATABASE_URL=${db}"
    sqlite3 "$db" "create table if not exists items (id integer primary key, name text);"

    echo "  port ${PWT_PORT}, database $(basename "$db")"
}
```

Three worktrees created through it:

```
     port 3001, database myapp_wt3001.sqlite3
     port 3002, database myapp_wt3002.sqlite3
     port 3003, database myapp_wt3003.sqlite3
-- start all three at once:
   x: up on 3001
   y: up on 3002
   z: up on 3003
   servers running simultaneously: 3 of 3
```

Two things carry the weight here, and neither is the copy. `PORT` is
**derived** from a number the tool allocates per worktree, so no two
worktrees can pick the same one. The database is **isolated** by naming it
after that same number, so a migration on one branch cannot reach another.

Note what the hook does not do: it never asks you which port is free, and it
never writes a registry. Deriving from an allocated number means there is
nothing to coordinate and nothing to clean up.

## Two traps when you write the hook yourself

Both cost me an afternoon, and both are silent.

**A substring replace is not a line replace.** Rewriting a key by swapping
the text `PORT=` looks right until the file already has a value in it: on
`PORT=3000` you get `PORT=50013000`, not `PORT=5001`. Match to the end of
the line so the old value is consumed.

**Check that the hook actually succeeded.** A setup step that dies halfway
leaves a worktree that looks ready and is not: the config was copied but
never rewritten, so it still carries the main checkout's port and database.
If your hook runs steps in a subshell, or anywhere its exit code is
discarded, a failure will look exactly like a success. Report the status,
and read it.

> Building a worktree setup hook with an agent? Have it verify by creating
> **three** worktrees and starting all of them, not one. Every failure in
> this post is invisible at N=1: a single worktree binds its port, owns its
> database, and looks perfectly correct.

The setup hook, the port allocation and the metadata behind
`$PWT_PORT` are part of [pwt](https://github.com/jonasporto/pwt), a Git
worktree manager for parallel development: `brew install jonasporto/pwt/pwt`.
Its reference Pwtfile walks through the derive/isolate/share decision for
databases, queues, caches and containers.
