---
layout: default
title: "Pwtfile"
description: "Project hooks: setup, server, custom commands, helpers and PWT_* variables."
permalink: /docs/pwtfile/
nav_order: 5
---

<p class="post-meta">Generated from <code>pwt</code> itself by
<code>scripts/gen-docs</code>. Do not edit by hand.</p>

# Pwtfile

```
PWTFILE
-------
Pwtfile is a bash file in your project root defining lifecycle hooks and
custom commands:

Core boundary:
  pwt manages worktrees, metadata, ports, navigation, jobs, and delegation.
  Project-specific dependencies, databases, workers, tests, and cleanup
  belong in Pwtfile commands.

Lifecycle Hooks:
  setup()       Runs after worktree created
  server()      Runs when "pwt server" called (use exec for stdin)
  server --kill Runs for "pwt remove --kill-server"
  teardown()    Runs when worktree removed
  doctor()      Runs as part of "pwt doctor" - project health checks
                (deps installed, registry auth, services reachable...)
  branch_name() Names the branch for "pwt create" ($1 worktree, $2 desc).
                Owns the project's naming convention; --branch still wins.

Custom Commands:
  xxx()         Any function becomes "pwt xxx"
  params        Passed as "$1", "$2", ... and raw "$PWT_ARGS"

Command Forms:
  pwt <project> <worktree> <cmd> [args...]  Run Pwtfile command from anywhere
  pwt <worktree> <cmd> [args...]            Run Pwtfile command inside project
  pwt <cmd> [args...]                       Run Pwtfile command inside worktree

Steps (for guided workflows):
  step_xxx()    Define with step_, list with "pwt steps", run with "pwt step xxx"

Configuration:
  PORT_BASE=4001         First port for worktrees (main app typically uses 4000)

Environment Variables (available in Pwtfile):
  $PWT_PORT              Allocated port for this worktree (e.g., 5001)
  $PWT_WORKTREE          Worktree name
  $PWT_WORKTREE_PATH     Full path to worktree
  $PWT_BRANCH            Git branch name
  $PWT_TICKET            Extracted ticket number (from branch name)
  $PWT_PROJECT           Project name
  $PWT_ARGS              Arguments passed to custom commands
  $PWT_KILL_TARGET       Delegated command from remove --kill-<command>
  $MAIN_APP              Path to main app (useful for copying files)

Helper Functions:
  pwtfile_symlink "path"      Symlink from main (e.g., .cache)
  pwtfile_copy "path"         Copy from main (e.g., .env)
  pwtfile_replace_literal     Safe string replacement
  pwtfile_git_exclude "pat".. Ignore files repo-locally (.git/info/exclude,
                              never committed, covers all worktrees)
  run <cmd>                   Run command (silent on error)

Tips:
  - Use "exec" in server() to keep stdin open for interactive commands
  - Copy local env files from $MAIN_APP: cp "$MAIN_APP/.env.local" . 2>/dev/null || true
  - For strict Pwtfiles (set -u), all PWT_* vars are pre-defined

Example:
  PORT_BASE=4001

  setup() {
      pwtfile_copy ".env.local"
      ./scripts/setup
  }
  server() { exec env PORT="$PWT_PORT" ./scripts/dev; }
  browse() { open "http://localhost:$PWT_PORT"; }


GLOBAL PWTFILE
--------------
Location: ~/.pwt/Pwtfile

Commands here work on ALL projects. Project Pwtfile overrides global.
Useful for shared utilities across projects.

```
