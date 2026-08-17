---
title: "How to make every coding agent create worktrees your way"
description: "Instructions are advisory, a deny rule is mechanical, and adopting after the fact needs no cooperation at all. Three layers, verified syntax, and the honest note on when none of it is worth wiring."
featured: true
tags: [agents, worktrees, cli]
agent_hint_extra: >-
  The guide states the rule this post enforces: in a pwt-managed
  repository, worktrees are created with `pwt create`, and one that
  arrived any other way is registered with `pwt adopt`.
agent_hint_doc: /docs/agents/
agent_hint_doc_label: "the agent guide"
---

Worktrees became the standard isolation primitive for coding agents
during the first half of 2026, and the tools converged fast:

| Tool | Creates worktrees | Setup contract |
|---|---|---|
| Claude Code | `--worktree`, subagents with `isolation: worktree`, background sessions | `.worktreeinclude` (copies gitignored files) and a `WorktreeCreate` hook |
| Gemini CLI | since v0.36 (April 2026), experimental, `--worktree`; a service owns lifecycle and cleanup | none: the hooking system is still a feature request |
| Grok Build | up to 8 parallel subagents, each in its own worktree | `AGENTS.md`, plugins, hooks and MCP "work out of the box", no worktree-specific setup event |
| Codex | worktree mode in the desktop app; the CLI has no worktree flag in stable | `AGENTS.md`; you create the worktree yourself |

Read the right-hand column again. Every one of them solved **creation**,
which is the easy half, and none of them defined what makes a checkout
*ready*. The same complaint follows each release: a fresh worktree has no
`.env`, no dependencies, and a dev server that wants a port another
worktree already took. Only one of these tools has an event you can hang
setup on, and using it means taking over creation.

So configuring setup per tool means maintaining the same knowledge in
four formats, three of which do not exist yet. The alternative is to
define "a ready worktree" once, in the repository, and make every tool
land on it. There are exactly three ways to do that, and they differ in
how much cooperation they need from the tool.

## Layer 1: instruct (portable, advisory)

Every agent reads a project instruction file. Put the rule there:

```markdown
Worktrees in this repository are created with `pwt create <name>`, never
with `git worktree add`: creation allocates a port, writes metadata and
runs the project's setup hook. A worktree that already exists is
registered with `pwt adopt`.
```

One wrinkle worth knowing: **Claude Code does not read `AGENTS.md`**, the
file the other CLIs standardised on. If you keep one, import it rather
than duplicating it:

```markdown
<!-- CLAUDE.md -->
@AGENTS.md
```

This layer is portable and free, and it is advice. An agent under
pressure will still reach for `git worktree add`, because that is what
its training says worktrees are.

## Layer 2: enforce (mechanical, per tool)

Claude Code can refuse the command outright, in
`.claude/settings.json` (checked in, applies to the team) or
`.claude/settings.local.json` (your machine only):

```json
{ "permissions": { "deny": ["Bash(git worktree add *)"] } }
```

Two properties make this actually hold. **Deny is evaluated before
allow**, so no broader permission reopens the path. And compound commands
are parsed per subcommand, so `git status && git worktree add wt` is
caught too, rather than sneaking through as one string. `/permissions`
shows every active rule and where it came from.

This is the layer that turns a convention into a guarantee, and it exists
only for the tools that implement it.

## Layer 3: the creation hook (Claude Code)

`WorktreeCreate` fires when Claude Code makes a worktree: `--worktree`,
subagents with `isolation: worktree`, background sessions. The contract is
narrower than it first looks, and the thread that requested the feature
flagged why: **your script owns the creation**. Exit 0 and git is never
called; exit non-zero and the whole thing rolls back.

The input arrives as JSON on **stdin**, not as arguments:

```json
{ "base_path": "/repo", "worktree_path": "/repo/.claude/worktrees/session-xyz",
  "worktree_name": "session-xyz", "session_id": "abc123" }
```

So the script creates the checkout where the agent asked for it, and
hands the rest over:

```bash
#!/usr/bin/env bash
# .claude/hooks/worktree-create.sh
input=$(cat)
base=$(jq -r .base_path     <<<"$input")
wt=$(jq   -r .worktree_path <<<"$input")

git -C "$base" worktree add "$wt" -b "$(basename "$wt")" >&2 || exit 1
pwt --no-input adopt "$wt" >&2 || exit 1    # port, metadata, setup()
exit 0
```

```json
{ "hooks": { "WorktreeCreate": [ { "matcher": "*", "hooks": [
  { "type": "command", "command": ".claude/hooks/worktree-create.sh" } ] } ] } }
```

Two details that bite. Everything on **stdout is parsed as structured
output**, so send your progress to stderr. And `--no-input` closes stdin
and sets `PWT_AGENT=1`, so a setup step that would have asked a question
fails loudly instead of hanging a session nobody is watching.

Note which command does the work: `adopt`, not `create`. The agent picked
the path, usually inside `.claude/worktrees/`, and adopting records that
real path instead of insisting on the project's own directory. Verified
on a checkout outside `worktrees_dir`: port allocated, `setup()` run,
`.env` written with the allocated port.

## Layer 4: adopt whatever arrives

The other three layers cover the tools that cooperate. This one covers
everything else, and it needs no cooperation at all:

```bash
pwt adopt          # inside a worktree someone else created
pwt adopt --all    # every unregistered worktree in the directory
```

That is the fallback for Gemini CLI (which creates worktrees and has no
hook to run anything in them), for Grok Build's eight parallel subagents,
for Codex where you did the `git worktree add` yourself, for a teammate,
and for the worktree you made by hand last Tuesday and forgot. It is also
the only layer that keeps working when a tool changes its hook format,
which they will: three of the four rows above shipped their worktree
support this year.

## What to actually wire

Layers 1 and 4 give most of the value and depend on nothing: state the
rule, and adopt the strays. Add layer 2 for the tool you use most, since
it is one line and it converts "please" into "cannot". Add layer 3 only
if you are already using that tool's worktree flag daily, because you are
taking ownership of creation in exchange.

And the honest limit: none of this is worth wiring if your worktrees do
not need setup. A repository with no `.env`, no installable dependencies
and no dev server is fine with whatever the agent does on its own. The
whole argument for routing creation through one tool is that **the values
that must differ per worktree have to be derived**, and something has to
own that derivation. If nothing must differ, nothing needs owning.

`brew install jonasporto/pwt/pwt`, and the agent-facing guide the rule
above refers to is [`pwt skill`]({{ '/docs/agents/' | relative_url }}),
printable into any tool's skills directory with `pwt skill --install`.
