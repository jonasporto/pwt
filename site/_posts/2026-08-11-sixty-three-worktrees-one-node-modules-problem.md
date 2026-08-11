---
title: "63 Git worktrees, one node_modules problem"
description: "Copying node_modules per worktree costs seconds and gigabytes. A homemade shared store almost worked; pnpm's copy-on-write clones actually did — with four gotchas found the hard way."
featured: true
---

The worktree workflow has one expensive corner: JavaScript dependencies. A
Git worktree is cheap — a checkout and some metadata. Its `node_modules` is
not. On a large Rails + Vite monolith I work on, a fresh worktree paid **17
seconds and 599MB** for `yarn install` with a warm cache. With 63 live
worktrees, letting every one of them install its own tree would mean ~29GB
of identical files.

The number that reframes the problem: hashing `yarn.lock` +
`package.json` across all 63 worktrees produced only **7 distinct
dependency sets**. Sixty-three trees, seven of which are actually
different. Everything else is duplication.

## Attempt one: a homemade shared store

The obvious move is deduplication: a content-keyed store (one entry per
dependency-set hash) and a per-package symlink farm in each worktree.
It worked, and it was fast — **67ms** to link a new worktree.

It also had a flaw that only shows up when someone uses it: the worktree's
`node_modules` *was* the shared store, reached through symlinks. Running
`yarn add` in one worktree rewrote packages under every other worktree on
the same key. Guarding that meant a read-only store, freeze/thaw helpers,
and a wrapper to intercept mutating commands — about 200 lines of machinery
to protect a design decision.

That is usually the sign to change the design.

## pnpm removes the problem instead of guarding it

pnpm keeps a global content-addressable store and materialises each
project's `node_modules` from it. On APFS (macOS) that materialisation uses
**copy-on-write clones**: every worktree gets its own real, writable tree
that costs almost no physical disk. Editing a file inside one worktree's
`node_modules` — or running `yarn add`-style mutations — touches nothing
anywhere else. Verified by editing a package in one project and diffing the
other: untouched.

Nothing shared is writable from a worktree, so the read-only store, the
freeze/thaw helpers and the command interception were all deleted.

| | homemade store + symlink farm | pnpm |
|---|---|---|
| install/link a worktree | 67ms | 3s |
| disk for all worktrees | 4.2GB | ~400MB |
| needs a guard on `yarn add` | yes | **no** |
| lifecycle-hook code | ~200 lines | ~60 |

3s instead of 67ms looks like a regression until you remember what it buys:
real trees, zero guards, and a tool someone else maintains.

Is the tree equivalent? Installing the same `yarn.lock` both ways and
diffing the **full** trees (not just the top level): of the 518 packages
the lockfile resolves to exactly one version, **0** were missing or at a
different version in the pnpm tree.

## Four gotchas, all found by doing it

**1. `nodeLinker: hoisted` only works from `pnpm-workspace.yaml`.** Not
`.npmrc`, not `package.json` — pnpm moved the setting. Put it in the wrong
place and you silently get the strict layout, where the build dies on the
first *phantom dependency*: a package your code imports but never declared,
which only resolved because yarn's flat layout happened to hoist it. The
app had four of them (starting with `@popperjs/core`). Hoisted mode
reproduces the flat layout while you declare them properly.

**2. Postinstall scripts need an explicit decision.** Recent pnpm refuses
to run dependency build scripts without approval — and then exits non-zero.
Audit what actually needs to build; in this app, all four flagged packages
were safe to skip (`--ignore-scripts`), and the build still exited 0.

**3. `pnpm import` is slow — cache its output.** Converting a `yarn.lock`
took ~76s. The derived `pnpm-lock.yaml` is cached per `yarn.lock` digest,
so each of the 7 dependency sets pays conversion once, ever.

**4. Some lockfiles cannot be converted at all.** `pnpm import` re-resolves
versions against the registry. A branch that pins a package version that
has since been unpublished fails the conversion — while `yarn install`
survives, because it fetches the exact tarball URL recorded in the
lockfile and never asks the registry for a version list. Old branches need
a yarn fallback; plan for it instead of fighting it.

## Bonus: the store only grows, and `prune` is not surgical

Two behaviours worth knowing before you rely on the store. Packages no
project references any more stay in the store forever — it never shrinks on
its own. And on APFS, `pnpm store prune` deletes **everything**, not just
orphans: pnpm counts hard links to decide what is referenced, but
copy-on-write clones show `nlink=1`, so every entry looks unreferenced.
Your projects keep working (their trees are independent clones); the next
install just pays a full re-download. Treat `prune` as "delete the cache",
not "clean the cache".

## Where this hooks into the worktree lifecycle

All of this belongs in the one place that runs on every worktree creation.
With [pwt](https://github.com/jonasporto/pwt) that is the `Pwtfile`'s
`setup()` hook: derive the dependency-set key, reuse the cached converted
lockfile, run the pnpm install, fall back to yarn for unconvertible
branches. New worktree, dependencies ready in ~3 seconds, and no human
remembers any of it.
