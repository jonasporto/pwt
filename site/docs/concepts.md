---
layout: default
title: "Concepts"
description: "What pwt means by worktree, project and Pwtfile."
permalink: /docs/concepts/
nav_order: 3
---

<p class="post-meta">Generated from <code>pwt</code> itself by
<code>scripts/gen-docs</code>. Do not edit by hand.</p>

# Concepts

```
CONCEPTS
--------
pwt manages git worktrees with automatic port allocation. Each worktree is an
isolated copy of your repo where you can work on a different branch without
switching branches in your main checkout.

Key concept: "pwt use" swaps a symlink. Your editor stays open pointing to
$(pwt current), and when you switch worktrees, it sees different code.

Worktree vs Clone:
  Worktree (default)     Faster, shares git objects, saves disk space
  Clone (--clone)        Full isolation, no branch locks, better for submodules

When to use worktrees:
  - Working on multiple features/tickets simultaneously
  - Testing changes without affecting main development
  - Code review while keeping your work intact
  - Comparing behavior between branches

```
