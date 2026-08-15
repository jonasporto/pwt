---
title: "The node_modules store I deleted is now a pnpm feature"
description: "pnpm's enableGlobalVirtualStore is the shared symlink store I built and abandoned. I re-measured with git worktrees: installs drop to 0.3s, node_modules drops to 140K, and one hand-edited file contaminates every worktree on the machine."
featured: true
tags: [worktrees, performance, env-config, agents]
---

Four days ago I wrote about [deleting a homemade dependency store]({{ '/blog/sixty-three-worktrees-one-node-modules-problem/' | relative_url }}):
a shared content-keyed store with a symlink farm in each worktree. It linked
a worktree in 67ms, and it needed about 200 lines of guard code to stop a
`yarn add` in one worktree from rewriting packages under every other one. I
deleted it and settled on pnpm's copy-on-write clones: 3 seconds instead of
67 milliseconds, in exchange for real, isolated trees and zero guards.

pnpm 11 ships the design I deleted. It is called
[`enableGlobalVirtualStore`](https://pnpm.io/global-virtual-store), it is
experimental, and pnpm's own docs now have a page recommending exactly this
setup [for git worktrees running parallel agents](https://pnpm.io/git-worktrees).
When the tool you migrated to starts shipping the design you abandoned, you
re-run your measurements. All numbers below are from today: pnpm 11.20.0,
macOS on APFS, a scratch repo with 7 direct dependencies (100 packages in
the tree), warm store, three worktrees.

## What it does to a worktree

One line in `pnpm-workspace.yaml`:

```yaml
enableGlobalVirtualStore: true
```

With it off (the default), each worktree gets a private `.pnpm` directory
of copy-on-write clones. With it on, `node_modules` becomes a thin layer of
symlinks into one machine-global directory, keyed by a hash of each
package's dependency subgraph:

```
$ readlink node_modules/react
~/Library/pnpm/store/v11/links/@/react/18.3.1/578b3b83.../node_modules/react
```

| | default (CoW clones) | global virtual store |
|---|---|---|
| install, warm store | ~0.55s | 0.60s first worktree, **~0.30s** after |
| `node_modules` on disk, per worktree | 57M | **~140K** |
| what a worktree owns | a real tree | symlinks |

Twice as fast and 400 times smaller per worktree. If those were the only
two numbers, this would be a short post.

## The problem my 200 lines guarded, solved properly

The reason I deleted my homemade store: mutations. Run `yarn add` in one
worktree and, through the shared symlinks, every worktree changed. My fix
was guard code. pnpm's fix is content addressing, and it holds up:

```
-- wt-a: pnpm add left-pad
-- wt-b: has left-pad?  no
-- wt-a: react still resolves to links/@/react/18.3.1 (same shared dir)
```

Adding a package changes the dependency graph, the changed graph hashes to
new directories, and the unchanged parts keep sharing the old ones. Nothing
mutates in place, so there is nothing to guard. This is the correct version
of what my 200 lines were trying to enforce, and someone else maintains it.

## The problem it reopens, with a bigger blast radius

Package-manager operations are safe. Hand edits are not, and hand edits are
a thing real debugging does: a `console.log` dropped into a dependency to
see what it receives, a quick experiment inside `node_modules` to test a
fix before reporting it upstream.

```
-- wt-a: append a line to node_modules/lodash/lodash.js
-- wt-b, same file, same instant:
   /* tampered from wt-a */
```

The symlink points into the shared store, so the edit lands in the shared
store. Every worktree with that dependency subgraph sees it immediately.
Then I created a brand-new worktree, `wt-d`, after the edit:

```
-- wt-d, freshly created, lodash.js last line:
   /* tampered from wt-a */
```

**The contamination is inherited by worktrees that did not exist when it
happened.** Under npm, yarn, or pnpm's default clones, a hand edit is
confined to one tree and dies with it. Under the global virtual store it is
machine-wide and persistent until repaired. `pnpm store status` does detect
it and `pnpm install --force` refetches, so there is a repair path. There
is just no prevention.

So the honest scorecard for the returned design: the mutation everyone
worries about (`pnpm add`) is solved by construction, and the mutation
nobody talks about (editing a file) got worse than every other layout. If
you need to patch a dependency, `pnpm patch` exists and produces a tracked,
per-project patch file, which is the sanctioned version of the hand edit.

## Your project can stay on yarn

The scratch repo above is a pnpm project, but none of this requires
migrating anything. The setup from the
[original post]({{ '/blog/sixty-three-worktrees-one-node-modules-problem/' | relative_url }})
still applies: `yarn.lock` stays the source of truth, and pnpm exists only
inside worktrees, in files git never sees. Three untracked files per
worktree: `pnpm-lock.yaml` (from `pnpm import`), `pnpm-workspace.yaml`
(the config above), and nothing else. To keep them out of `git status`,
put them in `.git/info/exclude`: it is local, never committed, and lives
in the repo's common directory, so one entry covers every worktree at
once. An agent running `git add -A` in that worktree commits nothing it
should not.

One trap cost me an hour, so here it is with the current answer. If the
project's `package.json` pins yarn via the `packageManager` field, pnpm 11
refuses to run at all in that directory, including `pnpm --version`:

```
ERROR  This project is configured to use yarn
```

Every bypass the internet suggests for this is dead. I tried
`packageManagerStrict: false` in `pnpm-workspace.yaml`, in `.npmrc`, as an
env var, as a CLI flag, and in global config; I tried
`COREPACK_ENABLE_STRICT=0`. All removed or no longer honored: pnpm 11's
changelog replaced the whole family with one setting. The one that works
today goes in the same untracked `pnpm-workspace.yaml`:

```yaml
enableGlobalVirtualStore: true
pmOnFail: warn
```

With that, the pinned-yarn project installs through pnpm in the worktree in
267ms, and the main checkout never learns pnpm was there.

## When to flip it

The decision is not speed. It is one question: **is `node_modules`
immutable in your workflow?**

- You (or your tools) sometimes edit files inside `node_modules` to debug:
  stay on the default copy-on-write clones. 3 seconds and 57M per worktree
  buys trees that cannot hurt each other.
- `node_modules` is strictly a build product, patches go through
  `pnpm patch`: the global virtual store gives you 0.3s installs and
  effectively free disk per worktree, which is what a workflow with many
  short-lived worktrees actually wants.

Also inherited from the docs, not measured here: the feature is
experimental, ESM imports do not respect `NODE_PATH` (some resolution
setups break), it does little in CI without a warm cache, and the store
assumes every user and agent writing to it is trusted.

> Running coding agents in worktrees? Agents debug by editing
> `node_modules` more casually than humans do, and with the global virtual
> store one such edit silently poisons every worktree on the machine,
> including ones created later, until `pnpm install --force` repairs the
> store. If you flip this flag, tell the agent `node_modules` is read-only
> and point it at `pnpm patch`.

The worktree lifecycle that makes this automatic (allocate the port,
derive the env, install the dependencies at creation) is what
[pwt](https://github.com/jonasporto/pwt) manages; the Pwtfile from the
[original post]({{ '/blog/sixty-three-worktrees-one-node-modules-problem/' | relative_url }})
needs only the two-line `pnpm-workspace.yaml` added to its `setup()` to
switch a project over: `brew install jonasporto/pwt/pwt`.
