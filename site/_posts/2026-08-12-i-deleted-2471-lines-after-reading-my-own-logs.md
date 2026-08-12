---
title: "I deleted 2,471 lines after reading my own logs"
description: "A TUI nobody ran, found by mining shell history and agent session logs. Humans navigate, agents execute, and neither one asks the CLI for a picture."
featured: true
---

The biggest single feature in pwt was `pwt status`, a full-screen dashboard
written in bash: **2,471 lines**, plus 621 lines of tests. I deleted all of
it. Not because it was broken, but because I finally counted.

Across **555 recorded invocations** of pwt, `pwt status` was run **twice**,
both times by me, inside pwt's own repository, while working on the
retirement itself. Outside the tool's own development it has no recorded use
at all.

Counting was two one-liners and about a minute. I had never run them.

## The two datasets

Anyone using an AI coding agent has a second usage log they did not know
they had. My shell history records what **I** type. The agent's session logs
record what **it** runs. Same CLI, two callers, and they turn out to want
completely different things.

The human side, a rolling window of my last 1,000 shell commands:

```bash
grep -aoE '(^|[;| ])pwt( [a-zA-Z0-9_.-]+)?' ~/.zsh_history \
  | sed -E 's/^[;| ]//' | sort | uniq -c | sort -rn
```

The agent side, every Bash command in 134 Claude Code session logs (433MB,
July 13 to August 12), pulled out of the `tool_use` entries:

```bash
rg -oaN --no-filename '"command":"[^"]{0,300}' ~/.claude/projects/*/*.jsonl \
  | rg -oa '(^|[;&|( ]|\\n)pwt [a-zA-Z0-9_.-]+' \
  | sed -E 's/.*pwt /pwt /' | sort | uniq -c | sort -rn
```

149 invocations from me, 406 from agents. Sorting each into what the call
actually does:

```
                  human (149)      agent (406)
navigate            114  (76%)       25   (6%)
execute              27  (18%)      330  (81%)
read                  6   (4%)       27   (7%)
write                 2   (1%)       24   (6%)
```

I did not expect the inversion to be that clean.

## What the split says

**I use pwt as a `cd` that knows things.** 114 of my 149 calls are
navigation, and most are the worktree-first form: `pwt some-ticket` to jump
there, or bare `pwt` to go to the current one. I am moving between
checkouts, and I want the shell to land somewhere with the right branch,
port and environment.

**Agents use pwt as an executor.** 330 of 406 agent calls take the form
`pwt run <worktree> <command>`: run the tests over there, start the server
over there, without disturbing the checkout the agent is sitting in. Agents
barely navigate at all, because they have no cwd worth preserving; they
address the worktree explicitly on every call.

**Neither one reads much.** 4% and 7%. And that is the number that killed
the TUI, because a dashboard is nothing but a read surface. I had spent
2,471 lines building the answer to a question almost nobody was asking the
CLI.

There is a reason both sides read so little, and it is different on each
side. The agent does not want a picture, it wants a value it can branch on,
which is what `--porcelain` and exit codes are for. And I do not ask the
CLI, because asking means stopping what I am doing, running a command,
reading it, and losing the terminal. When I actually wanted to know what was
running, I asked the agent sitting right there, and it answered from
`list`/`info`/`servers`. My reads were being proxied.

## Why the dashboard lost

A TUI you have to launch competes with whatever is already on your screen.
Mine lost that competition every single time, silently, for months, while I
kept it working and kept its tests green.

Deleting it was not "the feature was bad". It was in the wrong container. A
mission-control view wants to sit open in its own terminal tab all day and
push changes at you: which server is up, which agent job just finished,
which worktree is dirty. That is a persistent process with a state watcher,
and it has almost nothing in common with a bash function that paints a
screen once when invoked and exits.

So the read surface moved out of the CLI instead of being deleted outright.
It became a separate program consuming a versioned state contract, which is
also what forced pwt's internal state to become
[a format something else can read]({{ '/blog/sixty-two-processes-to-print-a-version-number/' | relative_url }}).
The CLI kept the two jobs its callers actually perform: navigate for the
human, execute for the agent.

## Where the numbers are soft

The measurements above are all reproducible today, but three of them are
weaker than they look, and pretending otherwise would be the whole mistake
this post is about.

**My shell history has no memory and no clock.** `SAVEHIST=1000` and no
`EXTENDED_HISTORY`, so the human dataset is exactly "the last thousand
commands", undated. It is a sample of a recent stretch, not a record. The
agent logs are the opposite: timestamped, complete for the period, and
deleted on their own schedule.

**Absolute counts drift, ratios hold.** The first time I ran this, in early
August, the same query over the corpus of that day returned 789 `pwt run`.
Today it returns 330, because sessions rotate out. Every conclusion here
rests on proportions between categories measured in one pass, never on a
count compared across passes.

**My extraction truncates.** Reading commands at 300 characters undercounts
long compound lines, and a name I invented that is not a subcommand gets
filed as navigation, which is usually right and occasionally a typo. Good
enough to see a 76/6 split; not good enough to argue about single digits.

And the honest correction: the first pass reported `pwt status` at **zero**
occurrences. Today's corpus has two, plus a couple in my shell history, all
of them after the retirement, all of them me poking at the thing I had just
removed. The conclusion did not change. The number I quoted did, and it was
quoted from a commit message rather than re-measured.

## What I would tell you to run

If you maintain a tool you use daily, you already have this data:

1. **Your shell history**, for what you do by hand. Turn on
   `EXTENDED_HISTORY` and raise `SAVEHIST` first, then wait a month and it
   becomes a real dataset instead of a sample.
2. **Your agent's session logs**, for what gets automated. This is the one
   nobody looks at, and for a CLI that agents drive it is now the larger
   half of usage.
3. **Sort invocations by what they do, not by name.** The category totals
   are what told me something; the per-command ranking mostly told me which
   worktrees I visit.

The feature I was proudest of was the one my own logs had never seen run.
That is a cheap thing to check and an expensive thing to assume.

> Asking an agent to mine this for you? Have it count `tool_use` commands
> from the session logs, not prose mentions in the transcript. Half the
> hits for `pwt status` in my corpus were skill documentation describing the
> command, not anyone running it.

pwt is a Git worktree manager for parallel development, now roughly 3,000
lines lighter: [github.com/jonasporto/pwt](https://github.com/jonasporto/pwt),
`brew install jonasporto/pwt/pwt`.
