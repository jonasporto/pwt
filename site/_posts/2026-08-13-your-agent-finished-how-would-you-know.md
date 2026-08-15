---
title: "Your agent finished. How would you know?"
description: "I shipped a blocking wait for background jobs so agents stop polling. Then I counted: my own agents used it 5 times in 23,770 commands and hand-rolled the wait loop instead."
featured: true
tags: [agents, jobs, cli]
---

I built `pwt jobs wait` so an agent could block on a background job instead
of asking "is it done yet" every thirty seconds. Then I counted how often my
agents actually used it.

Across 134 Claude Code session logs, **23,770 shell commands**:

```
sleep <n>                251
until ... done            75
while kill -0 <pid>       27
tail ... log             122
pgrep                    109
pwt jobs wait / server wait   5
```

**Five.** The primitive existed, was documented, and my own agents wrote
their own wait loop a hundred times instead. This post is about the problem,
the four ways the field solves it, and the honest conclusion about mine.

## What an agent writes when it has to wait

These are real commands out of my logs, with paths generalized:

```bash
until [ -f "$WORK/gate.DONE" ]; do sleep 60; done; cat "$WORK/gate.DONE"
```

```bash
while kill -0 91829 2>/dev/null; do sleep 30; done; echo "finished"
```

```bash
until ! pgrep -f 'parallel_rspec' >/dev/null; do sleep 60; done
```

Every one of those is a wait primitive, reinvented from scratch, in a
one-liner, by a model that had to pick the interval by guessing. Pick 60
seconds for a job that takes 12 and you waste 48 seconds of wall clock. Pick
5 for a job that takes 20 minutes and you have burned 240 tool calls and the
tokens for each of their outputs.

The failure mode nobody notices is the third one: `pgrep -f parallel_rspec`
matches the agent's own `until` loop in some shells, so the loop can exit
immediately or never. Hand-rolled waits are quietly wrong in ways nobody
reviews, because they live inside a command nobody reads twice.

This is a recognized problem, not my invention. Anthropic shipped a
[Monitor tool](https://www.mindstudio.ai/blog/claude-code-monitor-tool-stop-polling-background-processes)
in April 2026 specifically to replace polling with interrupt-driven waiting.

## Four ways the field handles background work

**Put it in a tmux pane.** This is the popular answer.
[workmux](https://github.com/raine/workmux) (2,179 stars) and
[claude-squad](https://github.com/smtg-ai/claude-squad) (8,304 stars) both
give each worktree its own pane or window, and you watch the fleet by
attaching.

It is genuinely good for a human. It is useless for an agent: a pane has no
exit code, no addressable id, and no way to answer "did it succeed" except by
scraping text off a screen. It also binds the tool to Unix, since there is no
native tmux on Windows.

**Refuse to own the process.** The category leader,
[worktrunk](https://github.com/max-sixty/worktrunk) (6,417 stars), states it
in its FAQ, verbatim: **"No long-running background processes or daemons"**.
That is a defensible design. It keeps the tool small, and it means the dev
server is your problem.

**Watch the output stream.** Claude Code's Monitor tool attaches to a running
process and fires when a pattern appears, like "Server running on port 3000".
This is the right shape, and it is first-party. Its scope is the session:
it watches a process the current session started.

**Keep a registry.** The process gets an id, a log file, a recorded pid and a
status, so anything can ask about it later, including a different session
tomorrow.

## What the registry buys, concretely

Start something in a worktree without holding the terminal:

```bash
pwt <worktree> <command> --bg
#   x-slowtask-1786647159
```

Then block on it, from anywhere, with one tool call:

```bash
$ pwt jobs wait x-slowtask-1786647159
x-slowtask-1786647159 stopped
# blocked 3.6s on a 4s job, exit 0
```

That is the whole point. One tool call, no interval to guess, an exit code to
branch on. Bound it when you do not trust the job:

```bash
$ pwt jobs wait x-slowtask-1786647173 --timeout 1
Timeout: job still running after 1s: x-slowtask-1786647173
Check it with: pwt jobs logs x-slowtask-1786647173
$ echo $?
5
```

Exit 5 means timeout, distinct from a job that ran and failed. For a server,
readiness is not process exit, so wait on the log line instead:

```bash
pwt server wait <worktree> --log-contains "Listening on"
```

And the state is queryable rather than scraped:

```bash
$ pwt jobs list --porcelain
[{"id":"x-slowtask-1786647173","command":"slowtask","worktree":"x",
  "project":"main","pid":17971,"log":".../x-slowtask-1786647173.log",
  "started_at":"2026-08-13T18:52:54Z","status":"stopped"}]
```

The difference that matters against a tmux pane is not ergonomics, it is
addressability. The job outlives the session that started it, it has a name
you can pass around, and the answer to "did it work" is an integer.

## When to use which

Honestly, most of these coexist. What decides is who is asking and how long
the thing lives.

| Situation | Reach for |
|---|---|
| You want to watch several agents work, with your eyes | tmux based tooling, and it is better at this than a registry |
| One process, this session, wake me when it prints something | the Monitor tool, interrupt driven and first party |
| An agent must branch on the result | a blocking wait that returns an exit code |
| The job outlives the session, or another session asks about it | a registry with ids and logs |
| You do not want the tool touching processes at all | worktrunk's position is a real one |

The registry is not better than a pane. It answers a different question, and
the question it answers is the one an agent asks.

## Questions this always raises

**Does the job die when I close the terminal?** No. Launching goes through a
double fork with `setsid`, and the daemon closes every inherited descriptor
above stderr. That last part is not pedantry:
[one leaked descriptor once hung a CI job for six hours]({{ '/blog/a-leaked-file-descriptor-hung-ci-for-six-hours/' | relative_url }}).

**How do I know it is ready, not just running?** Those are different
questions. Process exit is `jobs wait`, service readiness is
`server wait --log-contains`. A server that is running and not yet accepting
connections is the classic false green.

**Can two worktrees run the same service at once?** That is a port question,
not a job question, and it is answered by
[deriving the port per worktree]({{ '/blog/how-to-copy-env-into-a-git-worktree-and-what-it-breaks/' | relative_url }})
rather than copying it.

**What happens to jobs I forget?** They keep their record. `pwt jobs list`
shows them, `pwt jobs stop --all` ends them, `pwt jobs clean` drops stale
entries.

## The part I got wrong

Five uses in 23,770 commands is not a story about competitors lacking a
feature. It is a story about a feature nobody found, including the agents
running inside the repo that ships it.

The tool was not the problem: the primitive works, and every measurement in
this post came from running it. Discovery was the problem. An agent reaches
for `until ... sleep` because that is what it already knows, and it will keep
doing that until the tool's own documentation tells it, at the moment it is
about to wait, that a wait already exists.

That is why the agent-facing guide (`pwt skill`) leads with the wait
primitives now, and why the help text for `--bg` prints the wait command next
to the logs command. Whether that moves the number is measurable, and I will
report it either way.

> Shipping a primitive for agents? Grep your own session logs for the
> workaround it was meant to replace. If the workaround is still there, the
> primitive is not shipped, it is just written.

`pwt jobs`, `--bg` and the wait primitives are part of
[pwt](https://github.com/jonasporto/pwt), a Git worktree manager for parallel
development: `brew install jonasporto/pwt/pwt`.
