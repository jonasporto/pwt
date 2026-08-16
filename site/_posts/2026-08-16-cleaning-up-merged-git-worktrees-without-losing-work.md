---
title: "Cleaning up merged git worktrees without losing work"
description: "git worktree remove refuses dirty worktrees, --force destroys them, and git branch --merged cannot see a squash merge. I measured all three on one scratch repo, then wired the safe version."
featured: true
tags: [worktrees, cli, agents]
agent_hint_extra: >-
  Cleanup is in that guide: ask an agent to "remove the worktrees that are
  already merged" and it runs the preview first, because the destructive
  form needs an explicit flag it has to choose on purpose.
agent_hint_doc: /docs/commands/#auto-remove
agent_hint_doc_label: "pwt auto-remove"
---

Worktrees accumulate. Twenty directories in, you want the finished ones
gone, and the two commands everyone reaches for are
`git worktree remove` and `git branch --merged`. On one scratch repo with
four worktrees, both got it wrong: one destroyed uncommitted work, the
other could not see a merge that had already happened.

The four worktrees: `01-merged` (merged normally), `02-squashed` (merged
with squash, the way most PRs land), `03-open` (genuinely unfinished),
`04-dirty` (merged, but with an uncommitted file).

## `git branch --merged` cannot see a squash merge

The canonical way to find finished branches:

```
$ git branch --merged main
  TICKET-01-merged
  TICKET-04-dirty
```

`TICKET-02-squashed` is missing, and its work is already in `main`.
Squash merge replays the changes as one **new commit**, so the branch's
own commits are not ancestors of `main` and every ancestry-based check
calls it unmerged. Since most teams merge PRs with squash, the list you
would clean up is exactly the list of branches your workflow cannot
detect. Nothing errors; you just keep the directories forever.

This one has no free lunch, and I will not pretend otherwise: pwt's
check is ancestry-based too, so it also reports `02-squashed` as pending.
The difference is what happens next. An ancestry check that says
"pending" and therefore **keeps** the directory is a false negative you
clean up by hand; a tool that guessed and deleted would be a false
positive you cannot undo. If you want squash-merged branches detected,
the reliable signal is the forge (`gh pr list --state merged`), not git
ancestry.

## `git worktree remove` has exactly two settings

Point it at `04-dirty`, the merged worktree with an uncommitted file:

```
$ git worktree remove .../TICKET-04-dirty
fatal: '.../TICKET-04-dirty' contains modified or untracked files,
use --force to delete it
```

Correct refusal, useless suggestion. Git tells you the one flag that
makes it work, so that is the flag everyone types:

```
$ git worktree remove --force .../TICKET-04-dirty
$ cat .../TICKET-04-dirty/notes.txt
(gone)
```

The uncommitted file is not in any commit, not in any stash, not in the
reflog. `--force` is the only way past the refusal and it is unrecoverable.
"Refuse, or destroy" are the two options git offers, and in a directory
you already decided is finished, the refusal is the thing you are trying
to get past.

## The sweep, with the classification made explicit

The same repo, through `pwt auto-remove` (its alias is `pwt cleanup`),
which previews by default:

```
$ pwt auto-remove main --dry-run
Checking worktrees merged into: main

  ✅ MERGED: TICKET-01-merged
  ⏳ PENDING: TICKET-02-squashed
  ⏳ PENDING: TICKET-03-open
  ⚠️  DIRTY: TICKET-04-dirty - merged but has uncommitted changes

[DRY-RUN] Would remove 1 worktree(s):
  - TICKET-01-merged

Would keep: 3
```

Three states instead of two. Merged and clean is removable. Pending is
kept. **Merged but dirty is its own state**, and it is the one that
matters: the branch is finished, so a merge-based sweep would delete it,
and the uncommitted file would go with it. It is reported and kept.

Running it for real removes exactly what the preview promised:

```
$ pwt auto-remove main --execute
Removing: TICKET-01-merged
Done!
  Removed: 1
  Kept:    3
```

Two guards worth knowing. Non-interactively (an agent, a script, CI) the
command refuses to do anything without an explicit `--execute` or
`--dry-run`: a destructive sweep should never be what happens when
nobody was watching. And the branch is left alone; removing a checkout
and deleting history are different decisions, and `pwt remove
--with-branch` is where you say you meant the second one.

## When you do delete dirty work, it is recoverable

Sometimes the answer really is "yes, remove it, I know it is dirty".
That path keeps a copy:

```
$ pwt remove TICKET-03-open -y
?? notes.txt
Proceeding due to -y flag (changes will be LOST)
  ✓ Metadata saved to ~/.pwt/trash/TICKET-03-open_20260816_165157.trash
  ✓ Untracked files backed up to ~/.pwt/trash/..._untracked/

$ pwt restore list
Available backups:
  TICKET-03-open  2026-08-16 16:51:57  [untracked]
     Branch: TICKET-03-open
```

The file I "lost" is sitting in the trash directory, and
`pwt restore TICKET-03-open` puts it back. This is the difference
between `--force` as an escape hatch and `--force` as a shredder: git
has no copy of an untracked file, so a tool that removes worktrees has
to make one before it deletes.

## The shape of the rule

Cleanup is a classification problem wearing a deletion problem's
clothes. For every finished-looking worktree there are three questions,
and the usual tools answer only the first:

| Question | `git worktree remove` | `git branch --merged` | what you actually need |
|---|---|---|---|
| Is the branch merged? | does not ask | ancestry only (misses squash) | ancestry, plus the forge for squash |
| Is there uncommitted work? | refuses, or destroys | does not ask | keep it, or back it up first |
| Was this what you meant? | no preview | no preview | dry run by default |

`pwt auto-remove` (alias `pwt cleanup`) is the sweep with those three
answered:
[reference]({{ '/docs/commands/#auto-remove' | relative_url }}),
`brew install jonasporto/pwt/pwt`. The `git worktree remove` refusal is
still correct behaviour; it just needed a tool that treats "merged but
dirty" as a real answer instead of an obstacle.
