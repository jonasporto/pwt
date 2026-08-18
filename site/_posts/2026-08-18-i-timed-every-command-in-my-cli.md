---
title: "I timed every command in my CLI on a 95-worktree project"
description: "Four commands took over ten seconds. The fix was not making the work faster, it was taking the work off the read path. Includes the two instruments that lied to me and the command that is still slow today."
featured: true
tags: [performance, cli, bash]
agent_hint_extra: >-
  If you are scripting against pwt, read `pwt list --porcelain`: it is
  cached under the same contract as the table view and carries a
  `generated_at` epoch so you can judge how fresh the document is.
agent_hint_doc: /docs/commands/#list
agent_hint_doc_label: "pwt list"
---

Here is every command I use daily, timed this morning against a project
with 95 worktrees, on a machine holding 16 projects and 111 worktree
records:

| Command | Now |
|---|---|
| `pwt version` | 62 ms |
| `pwt list` | 44 ms |
| `pwt tree` | 53 ms |
| `pwt list --porcelain` | 245 ms |
| `pwt ports` | 256 ms |
| `pwt state --json` | 614 ms |
| `pwt servers` | **3054 ms** |
| `pwt list --refresh` | **13853 ms** |

Two months ago the first four were 13 to 17 seconds each. What changed is
not that the work got faster. Most of it did not.

## The numbers before

Measured then on the same project, which had 66 worktrees at the time:

| Command | Before | After |
|---|---|---|
| `pwt list --refresh` | 16.5 s | 12.7 s |
| `pwt list` (cached read) | 13 to 16 s | 0.03 s |
| `pwt tree` | 12.9 s | 0.05 s |
| `pwt servers` | 11.7 s | 1.9 s |
| `pwt state --json` | 2.4 s | 0.5 s |

Look at the first row against the second. The recompute got 23% cheaper,
which is a rounding error you would never feel. The read got 400 times
cheaper. Those two lines are the whole thesis.

## You cannot make the walk fast. You can stop putting it on the read.

Listing 95 worktrees means asking git 95 times what changed, and `git
status --porcelain` costs 120 ms in that repository. That is 11 seconds
of unavoidable work, and no amount of shell tuning removes it.

So the read stopped doing it:

- a cached list is served **immediately, even when stale**, with a note
  on stderr saying how old it is;
- the recompute runs in a **detached background process** that rewrites
  the cache for the next read;
- `--refresh` stays synchronous, because when you ask for fresh you are
  saying you will wait;
- the first run ever is synchronous too, since there is nothing to serve.

That is the trade, stated plainly: **you get milliseconds and you accept
that the answer may be a minute old.** For "what is dirty across my
worktrees" that is obviously fine. For "did my last command take effect"
it is not, which is why writing metadata invalidates the cache instead of
waiting for it to expire.

## The instrument that lied

**A serial trace blamed the wrong thing.** Running the list under `bash
-x` and counting external commands produced a satisfying culprit: 752
`tr` forks per list. It was real, and it was nearly free. Forks are cheap
and the trace flattened a parallel loop into a serial one, so the shape
of the cost was gone before I read it.

What found the real cost was comparing CPU to wall clock. `/usr/bin/time
-l` reported **79 seconds of system time for 14 seconds of wall**, which
says the work is spread across cores and dominated by syscalls, not by
process creation. That pointed at the filesystem, and from there at two
things: the status walk running **twice** per row (once to render, once
to decide merge status) and a `git fetch` costing 3 seconds on every list
that missed the cache.

The same lesson arrived a second time from a different direction, when a
commit message credited the startup win to the change that shipped
alongside the one that actually earned it. Re-measuring meant extracting
each commit with `git archive` and running all of them against identical
state, and the credit moved. That one has [its own
post]({{ '/blog/sixty-two-processes-to-print-a-version-number/' | relative_url }}),
including the part where the "faster" format was twice as slow on the
cold path.

## What actually made the recompute cheaper

Not one big thing. Six small ones, each removing repeated work rather
than optimising it:

- the status walk runs **once per row** instead of twice, with the merge
  check reusing the porcelain output already captured;
- status symbols come from parsing **one** `git status --porcelain` in
  bash, instead of three git commands piped through `wc` and `tr` (there
  go the 752 forks, worth about nothing, removed anyway);
- divergence uses one `--left-right --count` instead of two calls;
- commit hash and age share a single `git log`;
- column width for ASCII answers without forking;
- the row pool became a **rolling window** sized to the core count
  instead of a batch-of-4 barrier, so a slow row no longer stalls three
  idle workers.

**The dead end, since it was the obvious idea:** widening the pool past 8
on a 12-core machine made it *slower*, 13.6 s against 12.7 s. `git
status` is already multi-threaded and the contention is in the
filesystem, so more workers just fight each other.

## The bug that only appeared because of the fix

Serving stale caches needed tests, and the tests found something the
feature introduced: `list --refresh` **deleted the cache before
regenerating it**. For the seconds the recompute took, a concurrent
reader saw no cache file at all, and got the slow path or an empty
answer. Cache writes are now a temp file plus a rename, which is atomic,
and refresh overwrites rather than unlinking.

This is the ordinary tax on caching. The moment a read can be served from
a file, every writer has to think about who is reading it mid-write.

## Still slow, found while writing this

`pwt servers` is 3 seconds today, against the 1.9 s it measured at 66
worktrees: it grew with the project, which is the signature of work that
scales linearly with rows. I only looked at why because the table above
embarrassed me. Same method as before, CPU against wall:

```
3.14 real   1.32 user   1.62 sys
```

CPU almost equals wall, which means one core is busy the whole time:
**it is serial.** Counting its externals: 65 git invocations, one `lsof`,
one `ps`. The snapshot work already landed there (one `lsof` for the
whole machine instead of one per worktree, which is what took it from
11.7 s to 1.9 s), but the git calls never joined the parallel pool that
`pwt list` uses.

So the fix is not fewer git calls, it is the same rolling pool applied to
a second command. Measured, not guessed, which is the only part of this I
would insist on.

## Where the floor is

The cached porcelain read is 245 ms, and 62 ms of that is process
startup. Tracing it shows **five external commands in the whole run**.
The remaining time is bash walking 95 records and escaping their fields,
about 2 ms per record with no forks at all.

That is worth knowing before you optimise a shell tool further: once you
have stopped forking, what is left is the interpreter, and the only
remaining moves are doing less work per record or not being bash. There
is no third option hiding in there.

## If you are auditing your own CLI

1. **Time every command, not the one that annoys you.** The table is the
   deliverable. Mine had four entries over ten seconds and I had
   normalised all of them.
2. **Compare CPU to wall before profiling anything.** Wall much greater
   than CPU means waiting (network, locks). CPU close to wall means
   serial. CPU far above wall means parallel and syscall-heavy. Each
   points somewhere different, and it costs one command.
3. **Distrust fork counts from a serial trace.** They are easy to collect
   and they flatten exactly the structure you are trying to measure.
4. **Re-measure attributions, especially your own commit messages.**
   Extract the commits, run them against identical state, and let the
   numbers assign the credit.
5. **Ask whether the work belongs on the read path at all.** That
   question beat every optimisation in this list by two orders of
   magnitude.

`brew install jonasporto/pwt/pwt`. `pwt list` is served from cache and
tells you its age; `pwt list --refresh` is the one that waits
([reference]({{ '/docs/commands/#list' | relative_url }})). If you script
against it, `--porcelain` carries `generated_at` so you can decide for
yourself whether the document is fresh enough.
