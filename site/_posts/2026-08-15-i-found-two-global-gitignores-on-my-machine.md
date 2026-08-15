---
title: "I found two global gitignores on my machine. Both were the wrong layer."
description: "Agent configs, derived lockfiles, generated files: every worktree needs them, no commit should contain them. The usual answer is a global gitignore, and mine was hiding 36 files across 10 repos, one of which tracks the files it hid."
featured: true
tags: [worktrees, env-config, agents]
---

Modern worktrees fill up with files that must exist and must never be
committed: agent configuration (`.claude/`, `AGENTS.md`, `.mcp.json`), a
[derived `pnpm-lock.yaml` in a yarn project]({{ '/blog/the-node-modules-store-i-deleted-is-now-a-pnpm-feature/' | relative_url }}),
generated Procfiles, review-tool state. The standard answer is a global
gitignore in `core.excludesFile`, and that is what I had. This week I
audited it before retiring it, and the audit is the argument.

What I found on one machine: **two** global ignore files with identical
content, because a conditional include (`includeIf "gitdir:..."`) pointed
work repos at a second copy. `core.excludesFile` is single-valued, so the
second file did not add to the first; it silently replaced it. The two
files matched today only because one started as a copy of the other, and
nothing would have kept them matching. Together they were hiding **36
files across 10 repos**, and in one repo they were hiding a directory the
repo deliberately **tracks** ten files inside.

That last one is the real cost. Ignore rules never affect tracked files,
so nothing broke. But the next intentional file of that name, in the one
repo where it belongs in a commit, is born invisible: `git status` will
not mention it, and you will not commit it, and nothing will tell you.

## The four layers, and what each is for

| Layer | Committed? | Scope | Travels with |
|---|---|---|---|
| `.gitignore` | yes | this repo, everyone | the repo |
| `.git/info/exclude` | never | this repo, this machine | nothing (but see below) |
| `core.excludesFile` (global) | never | every repo on the machine | nothing |
| per-worktree, via `extensions.worktreeConfig` | never | one worktree | nothing |

Two facts decide everything:

**Layers are additive, but `core.excludesFile` is one value.** All four
sources combine when git decides what to ignore. But the global layer is a
single config key: set it again in an included config and the old file
stops applying entirely. That is how machines end up with two registries
and nobody noticing.

**`.git/info/exclude` lives in the repo's common directory.** A worktree's
`.git` is a pointer file; the real directory, including `info/exclude`, is
shared by every worktree of the repo. One line in that file ignores the
pattern in the main checkout and in all worktrees, current and future, and
can never reach a commit because git does not track its own metadata.

That second fact makes `info/exclude` the right home for exactly the
files this post is about: repo-specific, machine-local, worktree-borne.
The global file is the right home for almost nothing: the classic
`.DS_Store` case, and even that is arguable.

The fourth layer exists but read the fine print before wanting it:
per-worktree config requires `extensions.worktreeConfig`, and a
per-worktree `core.excludesFile` *replaces* the global one for that
worktree instead of adding to it. Since ignore patterns for files that do
not exist are free, I have yet to find a case where the union of patterns
in `info/exclude` is not simpler.

## Migrating off the global, mechanically

The dangerous move is deleting the global first: the moment it stops
applying, every file it was hiding shows up as `??` in every repo at once,
and an agent running `git add -A` will happily commit your agent config
into a work repo. So the order is: write the per-repo entries first, prove
they cover everything, delete the global last.

No guessing is needed at any step. Git will tell you exactly what the
global is hiding, per repo:

```bash
# what status looks like today vs. with no global ignore
diff <(git status --porcelain) \
     <(git -c core.excludesFile=/dev/null status --porcelain)

# for each path that appeared: which pattern (and which file) hid it
git check-ignore -v -- <path>
```

Every line the diff produces is a fact: this repo depends on that global
pattern. `check-ignore -v` names the pattern and the file it came from,
which is also how I discovered registry number two. The migration is then:
append exactly those patterns to that repo's `.git/info/exclude`, re-run
the diff everywhere until it is empty everywhere, and only then empty the
global file. I ran this across 90+ checkouts; the whole thing is an hour,
most of it waiting on `git status`.

The repos that needed nothing got nothing, which is the point. A global
pattern is a claim about every repo you will ever clone. A line in
`info/exclude` is a claim about one repo, and it can be wrong without
poisoning the others.

## Making it reproducible

`info/exclude` has one genuine weakness: it travels with nothing. A new
machine, a teammate, a re-clone all start from an empty file, and the
knowledge of what to exclude lives nowhere.

So give it a source of truth that is committed, without committing the
excludes themselves. As of this week, a
[pwt](https://github.com/jonasporto/pwt) Pwtfile can declare them:

```bash
# Pwtfile - setup() runs on every `pwt create`
setup() {
    pwtfile_git_exclude "pnpm-lock.yaml" "pnpm-workspace.yaml" ".claude/"
}
```

`pwtfile_git_exclude` appends each pattern to the repo's common
`.git/info/exclude`, idempotently, so declaring it on every create costs
nothing and a fresh machine converges on the first worktree it creates.
The Pwtfile is committed; the exclude file never is. The declaration
travels, the state stays local.

> Running agents in your worktrees? This failure is agent-shaped on both
> ends: agents generate exactly the files that need excluding, and agents
> run `git add -A` without reading the status first. A pattern declared in
> the Pwtfile closes the loop before either happens.

`pwtfile_git_exclude` ships in pwt as of this week, alongside the port
allocation and setup hooks from the
[earlier]({{ '/blog/how-to-deal-with-port-allocation-in-git-worktrees/' | relative_url }})
[posts]({{ '/blog/how-to-copy-env-into-a-git-worktree-and-what-it-breaks/' | relative_url }}):
`brew install jonasporto/pwt/pwt`.
