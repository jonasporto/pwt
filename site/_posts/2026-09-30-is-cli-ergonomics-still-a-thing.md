---
title: "Is CLI ergonomics still a thing?"
description: "We type fewer commands than a year ago; the prompts got longer. What still goes into a shell is a reaction to something on screen, and that is where a CLI earns its keep."
featured: true
tags: [cli, agents, worktrees]
---

Last week I typed three commands that did not exist.

```
$ git checkout feature/login
fatal: 'feature/login' is already checked out at '/home/me/app-worktrees/login'
$ pwt it
^C
$ pwt there
^C
$ pwt @in
```

They were not guesses at syntax I had forgotten. I knew none of them
existed. I typed them the way you say a word you wish existed: git had
just refused, the path was right there in its own error, and the next
action could not possibly be typing all of that again. What I actually
wanted was for a past version of me to have thought of this already.

## We type fewer commands. What still goes into the shell changed.

Most of the commands run on my machine this year were not typed by me. An
agent runs the long sequences: create the worktree, install, run the suite,
read the log, run it again, write the commit. The typing did not go away;
it moved into prompts, and the prompts got long. What shrank is the part
that goes into a shell. My own shell history is short and strange. It is
full of one-word interjections between agent turns:
`pwt -`, `git diff`, `pwt logs`, and a lot of things I typed right after
reading an error.

That is the shift. Typing used to be labor: fifteen commands to get from
"idea" to "server running", and ergonomics meant shaving keystrokes off
each of them. The agent took the labor. What is left for the hands is
reaction: something just happened on screen, I am reading it, and I want
to answer it in one gesture, while the thought is still there.

It also raised the bar. Once you stop typing commit messages, a four-step
copy and paste stops feeling normal. Flows I accepted for fifteen years now
feel broken, not because they got worse, but because everything around them
got effortless.

Fewer commands, each one worth more. Ergonomics did not go away with
agents. It concentrated.

## The tax is transcription

Look at the failed checkout again. Everything I need is already on screen:
git knows which worktree holds the branch and prints the path. The only
thing between me and that directory is moving text from one place on the
screen to another. Select, copy, type `cd `, paste. Four steps to transport
information the computer already has in memory.

On an ordinary day that is a small tax. At the moment of reaction it is the
whole cost, because the alternative is one word.

## Pointing words

pwt already had two. `pwt @` goes to the main checkout. `pwt -` goes back
to where you were. They are not abbreviations of longer commands. They are
the shell equivalent of "home" and "back": the words you use when you are
pointing at something instead of naming it.

`pwt @there` is the third one: go to the thing that was just pointed at.

{% include demo.html src="05-there" caption="git refuses, @there goes where it pointed, @ comes home. Nothing copied." %}

The obvious objection: the shell already has this. `!$` expands to the last
argument of the previous command, so `pwt cd !$` would have worked on day
one, given a `cd` that understands branch names (pwt did not have that
either; it does now). I know `!$`. I have known it for fifteen years. I did
not reach for it, and I doubt you would have. Under friction you reach for
a word, not for history expansion syntax. `@!` was the other candidate and
it loses on the same test, plus one more: `!` triggers history expansion in
zsh, so it would need quoting.

## What the binary cannot see

The mechanism has one interesting constraint. pwt is a bash script that
runs as a subprocess. By the time it starts, git's error is gone, and so is
the command line that caused it. A subprocess does not get to read its
parent's history.

The shell function does. `pwt shell-init` generates a function that wraps
the binary (it has to: a subprocess cannot change your directory either).
Inside a function, `fc -ln -1` returns the previous line from the
interactive shell's history, in both zsh and bash. The wrapper reads it
when any argument is `@there`, exports it as a local variable for the
duration of the call, and the binary does the rest.

The rest is deliberately dumb. The binary does not parse git's error
message. It takes the previous command line, walks the words from the end
skipping flags and redirections, and asks `git worktree list` which
worktree has that branch checked out. Same source of truth as the error,
so the answer is the path git refused, every time.

Not parsing the message paid for itself within the hour. The test I wrote
asserted on "is already checked out at". It passed on my Mac and failed on
the Linux runners: git 2.46 changed the wording to "is already used by
worktree at". The feature never noticed. The test did.

## Two callers, two ergonomics

The agent does not need `@there`. It is not reading a screen; it has the
branch name as a string already. For it, the explicit form is the ergonomic
one: `pwt cd feature/login`, `pwt run feature/login make test`. Both
resolve branch names now, through the same function.

That is the answer to the title. CLI ergonomics is still a thing, and there
are two of them now. The agent wants explicit, idempotent, machine-readable:
no history, no state, no pointing. The human wants deixis: here, back,
there. A CLI in 2026 serves both, and the trick is that they share the
resolver and differ only in the first word.

## Try it

Ships in pwt 0.2.14: `npm i -g @jonasporto/pwt` or
`brew install jonasporto/pwt/pwt`, then `eval "$(pwt shell-init)"` in your
shell rc if it is not there already. Next time git refuses a checkout, type
the one word.
