---
title: "63 Git worktrees, one node_modules problem"
description: "63 worktrees, 7 real dependency sets: pnpm's copy-on-write clones replaced 29GB of copied node_modules. Gotchas included."
featured: true
tags: [worktrees, env-config, performance]
cover: /assets/covers/node-modules-gravity.png
image:
  path: /assets/covers/node-modules-gravity-card.png
  width: 1200
  height: 630
cover_alt: "Heaviest objects in the universe: Sun, neutron star and black hole bend spacetime a little; node_modules bends it off the chart"
---

The worktree workflow has one expensive corner: JavaScript dependencies. A
Git worktree is cheap, a checkout plus some metadata. Its `node_modules` is
not. On a large Rails + Vite monolith I work on, a fresh worktree paid **17
seconds and 599MB** for `yarn install` with a warm cache. With 63 live
worktrees, giving every one its own tree would mean ~29GB of identical
files.

Then I measured the number that reframes the problem: hashing `yarn.lock` +
`package.json` across all 63 worktrees produced only **7 distinct
dependency sets**. Sixty-three trees, seven actually different. Everything
else is duplication.

## Attempt one: a homemade shared store

The obvious move is deduplication. A content-keyed store (one entry per
dependency-set hash) and a per-package symlink farm in each worktree. It
worked, and it was fast: **67ms** to link a new worktree.

It also had a flaw that only shows up when someone uses it. The worktree's
`node_modules` *was* the shared store, reached through symlinks. Running
`yarn add` in one worktree rewrote packages under every other worktree on
the same key. Guarding that meant a read-only store, freeze/thaw helpers,
and a wrapper intercepting mutating commands: about 200 lines of machinery
protecting a design decision.

That much guard code is usually the sign to change the design.

## pnpm removes the problem instead of guarding it

pnpm keeps a global content-addressable store and materialises each
project's `node_modules` from it. On APFS (macOS) that materialisation uses
**copy-on-write clones**: every worktree gets its own real, writable tree
that costs almost no physical disk. I verified the isolation directly by
editing a package inside one worktree and diffing the other. Untouched.

Nothing shared is writable from a worktree, so the read-only store, the
freeze/thaw helpers and the command interception were all deleted.

| | homemade store + symlink farm | pnpm |
|---|---|---|
| install/link a worktree | 67ms | 3s |
| disk for all worktrees | 4.2GB | ~400MB |
| needs a guard on `yarn add` | yes | **no** |
| lifecycle-hook code | ~200 lines | ~60 |

3s instead of 67ms looks like a regression until you count what it buys:
real trees, zero guards, and a tool someone else maintains.

Is the tree equivalent? I installed the same `yarn.lock` both ways and
diffed the **full** trees, not just the top level. Of the 518 packages the
lockfile resolves to exactly one version, **0** were missing or at a
different version in the pnpm tree.

## Four gotchas, all found by doing it

**1. `nodeLinker: hoisted` only works from `pnpm-workspace.yaml`.** Not
`.npmrc`, not `package.json`. pnpm moved the setting, and putting it in the
wrong place silently gives you the strict layout, where the build dies on
the first *phantom dependency*: a package your code imports but never
declared, resolving only because yarn's flat layout happened to hoist it.
The app had four of them (starting with `@popperjs/core`). Hoisted mode
reproduces the flat layout while you declare them properly. If your code
has no phantom dependencies, current pnpm's default isolated linker works
as is; hoisted is the bridge, not the destination.

**2. Postinstall scripts need an explicit decision.** Recent pnpm refuses
to run dependency build scripts without approval, and then exits non-zero.
Audit what actually needs to build. In this app all four flagged packages
were safe to skip (`--ignore-scripts`), and the build still exited 0.

**3. `pnpm import` is slow. Cache its output.** Converting a `yarn.lock`
took ~76s. Caching the derived `pnpm-lock.yaml` per `yarn.lock` digest
means each of the 7 dependency sets pays conversion once, ever.

**4. Some lockfiles cannot be converted at all.** `pnpm import` re-resolves
versions against the registry. A branch pinning a package version that has
since been unpublished fails the conversion, while `yarn install` survives:
it fetches the exact tarball URL recorded in the lockfile and never asks
the registry for a version list. Old branches need a yarn fallback. Plan
for it instead of fighting it.

## Bonus: the store only grows, and `prune` is not surgical

Two behaviours worth knowing before you rely on the store. Packages nothing
references any more stay in the store forever; it never shrinks on its own.
And on APFS, `pnpm store prune` deletes **everything**, not just orphans.
pnpm counts hard links to decide what is referenced, but copy-on-write
clones show `nlink=1`, so every entry looks unreferenced. Your projects
keep working (their trees are independent clones); the next install pays a
full re-download. Treat `prune` as "delete the cache", not "clean the
cache".

## Wiring it into the worktree lifecycle

All of this belongs in the one place that runs on every worktree creation.
With [pwt](https://github.com/jonasporto/pwt) that is the `Pwtfile`, the
per-project file where you define what "set up a worktree" means. This
exact file was written and verified by an agent driving pwt in a scratch
repo (two worktrees created, isolation checked by tampering one tree and
diffing the other, fallback proven by breaking pnpm on purpose):

```bash
# Pwtfile - runs on `pwt create` for every new worktree

setup() {
    node_deps
}

# Fast, isolated node_modules per worktree:
# yarn.lock stays the source of truth; pnpm does the installing.
# `pnpm import` (yarn.lock -> pnpm-lock.yaml) is paid once per lockfile
# hash, then cached, so every later worktree skips straight to install.
node_deps() {
    local key lockcache
    key=$(cat yarn.lock package.json | shasum | cut -d' ' -f1)
    lockcache="${PWT_DIR:-$HOME/.pwt}/cache/$PWT_PROJECT/pnpm-locks/$key"

    if [ -f "$lockcache/pnpm-lock.yaml" ]; then
        cp "$lockcache/pnpm-lock.yaml" .
    elif pnpm import; then
        mkdir -p "$lockcache"
        cp pnpm-lock.yaml "$lockcache/"
    else
        # pnpm couldn't convert this lockfile - fall back to plain yarn
        yarn install --frozen-lockfile
        return
    fi

    pnpm install --frozen-lockfile --ignore-scripts
}
```

In the scratch repo the second worktree's whole `pwt create` took 1.0s
against 2.5s for the first (which pays the `pnpm import`). On the real
monolith the same shape lands at ~3s per worktree.

`pwt create feature-x` runs `setup()` in the new worktree. Dependencies are
ready in about 3 seconds, the disk stays flat no matter how many worktrees
exist, and nobody has to remember any of this. That is the actual pitch for
worktree tooling: the one-time cost of figuring this out gets encoded once,
in the Pwtfile, and every branch after that just works.

> You don't need to copy this by hand. If you work with an AI agent, point
> it at your repo and ask it to build the Pwtfile: `pwt skill` prints the
> agent guide (porcelain output, exit codes, wait primitives), and the agent
> can test its own `setup()` by creating a throwaway worktree.
{: .hint-agent}
