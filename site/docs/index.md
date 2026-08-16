---
layout: default
title: "Documentation"
description: "pwt documentation: concepts, commands, navigation, Pwtfile hooks, and the agent guide."
permalink: /docs/
nav_order: 1
---

<p class="post-meta">Generated from <code>pwt</code> itself by
<code>scripts/gen-docs</code>. Do not edit by hand.</p>

# Documentation

pwt manages Git worktrees across projects: per-worktree ports, setup
hooks, background jobs, and navigation.

```bash
brew install jonasporto/pwt/pwt     # or: npm i -g @jonasporto/pwt
cd ~/projects/myapp && pwt init
```

- [Concepts](concepts/) - what a worktree is here, and when pwt beats raw `git worktree`
- [Command reference](commands/) - every command's own `--help`
- [Navigation](navigation/) - `cd`, aliases, partial names, multi-project
- [Pwtfile](pwtfile/) - hooks, helpers and the `PWT_*` variables
- [For agents](agents/) - the guide `pwt skill` prints

Every page here is generated from the installed binary, so it always
matches the version you are running. Longer form writing, with
measurements, lives on the [blog](../blog/).
