---
title: "How to add an existing repo to pwt"
description: "One command inside the repo, three lines of state outside it, nothing written into your project. What pwt init actually does, how to navigate with a two-letter alias, and how to undo all of it."
featured: true
tags: [cli, worktrees]
---

You have a repo already cloned and you want it managed by
[pwt](https://github.com/jonasporto/pwt): allocated ports, worktrees with
setup hooks, background jobs, and two-keystroke navigation. The whole
onboarding is one command, run inside the repo:

```
$ cd ~/Projects/pwt-ui && pwt init
✓ Configured: pwt-ui

path=/Users/jonasporto/Projects/pwt-ui
worktrees_dir=/Users/jonasporto/Projects/pwt-ui-worktrees
remote=git@github.com:jonasporto/pwt-ui.git
```

That output is not a summary of what happened. It is the *entirety* of
what happened: those three lines are the complete contents of the one
file pwt created, and this post is short because there is honestly not
much more to it.

## Where the state lives, and where it does not

Everything landed outside your repo, in `~/.pwt/projects/<name>/config`,
as plain `key=value` text. Inside the repo: nothing. No dotfile, no hook,
no config edit; `git status` before and after are identical. The
`worktrees_dir` was not even created yet, because it is not needed until
the first worktree is.

That asymmetry is deliberate, and it makes un-registering trivial:

```bash
rm -rf ~/.pwt/projects/pwt-ui   # pwt forgets the project; the repo never knew
```

There is nothing to uninstall from the repo because nothing was installed
into it. If you try pwt for one project and hate it, the exit is one
`rm` of pwt's own state.

The variant for a repo you have not cloned yet does both steps at once:

```bash
pwt init git@github.com:you/app.git   # clone + register
```

## The part you will use fifty times a day

Registration buys you the navigation. With the shell integration active
(`eval "$(pwt shell-init)"` in your shell rc), the project name is now a
`cd` from anywhere:

```
$ pwt pwt-ui        # from any directory: cd to the repo
$ pwt pwt-ui list   # or run commands against it without cd'ing
```

The name is still four syllables, so give it an alias:

```
$ pwt alias ui
✓ pwt-ui → ui
```

`pwt ui` from anywhere in the filesystem now lands in the repo, and
`pwt ui <worktree>` lands in a specific worktree of it. For a project you
enter dozens of times a day, this is the feature that pays the
registration back within the hour.

And the worktree name does not have to be the worktree name. Any unique
fragment matches, which in practice means the ticket number is the whole
address:

```
$ pwt 1234                 # worktree is TICKET-1234-fix-login
~/Projects/app-worktrees/TICKET-1234-fix-login

$ pwt 1240                 # fragment matches two worktrees
Multiple matches for '1240':
  TICKET-1240-api
  TICKET-1240-api-retry
```

Unique fragment: you are there. Ambiguous fragment: pwt lists the
candidates and refuses to guess, which is the correct behavior at 4pm
with six worktrees named almost the same thing.

## What the registration unlocks later

Nothing above touched worktrees, and that is the point: registration is
cheap and separate. When the project needs them, the machinery from the
earlier posts is already wired to the name:

- `pwt create feature-x` gives the worktree
  [a port that survives everything]({{ '/blog/how-to-deal-with-port-allocation-in-git-worktrees/' | relative_url }})
- a `Pwtfile` in the repo root turns "set up a worktree" into
  [code that runs on every create]({{ '/blog/how-to-copy-env-into-a-git-worktree-and-what-it-breaks/' | relative_url }}),
  including [worktree-only git excludes]({{ '/blog/how-to-gitignore-per-worktree/' | relative_url }})
- `pwt server --bg` and `pwt jobs wait` give agents
  [something better than polling]({{ '/blog/your-agent-finished-how-would-you-know/' | relative_url }})

The repo in the transcript is real: pwt-ui, the terminal dashboard for
pwt I am building, is now managed by the tool it fronts. Registering it
took under a minute, and dogfooding it immediately caught a real bug
(`pwt init` through the shell wrapper registered a ghost project named
after an internal command; fixed, with a regression test, before this
post went up). Adding your repo to the tool that manages your repos is
apparently also a test suite.

`brew install jonasporto/pwt/pwt`, then `pwt init` inside the repo you
use most. The alias goes in the same minute.
