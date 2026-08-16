---
layout: default
title: "Navigation"
description: "Moving between worktrees and projects: cd, aliases, partial names."
permalink: /docs/navigation/
nav_order: 4
---

<p class="post-meta">Generated from <code>pwt</code> itself by
<code>scripts/gen-docs</code>. Do not edit by hand.</p>

# Navigation

```
NAVIGATION
----------
pwt cd <worktree>        Go to worktree directory
pwt <worktree>           Go to worktree directory (inside a project)
pwt <project> <worktree> Go to another project's worktree
pwt cd @                 Go to main app (original checkout)
pwt cd -                 Go to previous worktree
pwt use <worktree>       Switch symlink (editor stays open at $(pwt current))

Shell Integration (add to ~/.zshrc):
  eval "$(pwt shell-init)"

After shell-init:
  $PWT_WORKTREE          Current worktree name (when in worktree)
  $PWT_PREVIOUS_PATH     Previous path (enables 'pwt cd -')

Multi-Project Navigation:
  pwt auto-detects project from current directory. From anywhere:
    pwt myproject list
    pwt myproject create TICKET-123 main
    pwt --project myproject list

  Project as first arg or use --project flag.

```
