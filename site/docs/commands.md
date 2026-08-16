---
layout: default
title: "Command reference"
description: "Every pwt command, straight from its own --help output."
permalink: /docs/commands/
nav_order: 2
---

<p class="post-meta">Generated from <code>pwt</code> itself by
<code>scripts/gen-docs</code>. Do not edit by hand.</p>

# Command reference

Run any of these with `--help` in your terminal for the same text.
Each command has a stable anchor, so `/docs/commands/#create`
links straight to it.

<p class="cmd-index"><a href="#create"><code>create</code></a>
<a href="#add"><code>add</code></a>
<a href="#track"><code>track</code></a>
<a href="#adopt"><code>adopt</code></a>
<a href="#setup"><code>setup</code></a>
<a href="#list"><code>list</code></a>
<a href="#ls"><code>ls</code></a>
<a href="#tree"><code>tree</code></a>
<a href="#skill"><code>skill</code></a>
<a href="#cd"><code>cd</code></a>
<a href="#use"><code>use</code></a>
<a href="#current"><code>current</code></a>
<a href="#info"><code>info</code></a>
<a href="#show"><code>show</code></a>
<a href="#remove"><code>remove</code></a>
<a href="#rm"><code>rm</code></a>
<a href="#server"><code>server</code></a>
<a href="#s"><code>s</code></a>
<a href="#gateway"><code>gateway</code></a>
<a href="#servers"><code>servers</code></a>
<a href="#run"><code>run</code></a>
<a href="#for-each"><code>for-each</code></a>
<a href="#diff"><code>diff</code></a>
<a href="#repair"><code>repair</code></a>
<a href="#fix"><code>fix</code></a>
<a href="#auto-remove"><code>auto-remove</code></a>
<a href="#cleanup"><code>cleanup</code></a>
<a href="#restore"><code>restore</code></a>
<a href="#fix-port"><code>fix-port</code></a>
<a href="#doctor"><code>doctor</code></a>
<a href="#state"><code>state</code></a>
<a href="#meta"><code>meta</code></a>
<a href="#m"><code>m</code></a>
<a href="#project"><code>project</code></a>
<a href="#config"><code>config</code></a>
<a href="#port"><code>port</code></a>
<a href="#plugin"><code>plugin</code></a>
<a href="#step"><code>step</code></a>
<a href="#alias"><code>alias</code></a>
<a href="#jobs"><code>jobs</code></a>
<a href="#logs"><code>logs</code></a>
<a href="#self"><code>self</code></a>
<a href="#versions"><code>versions</code></a>
</p>

## pwt create {#create}

```
Usage: pwt create|add <branch> [base] ["description"]

Arguments:
  branch          Branch name or ticket (e.g., TICKET-1234)
  base            Base branch (default: master)
  "description"   Quoted text with spaces is treated as description

Options:
  --from <ref>      Create from specific ref (tag, commit, branch)
  --from-current    Create from current branch
  --branch <name>   Use exact Git branch name (directory still uses <branch>)
  --track <remote/ref>
  --track-existing <remote/ref>
                    Create local branch tracking an existing remote branch
  --clone           Use git clone instead of worktree
  -e, --editor      Open in editor after creation
  -n, --dry-run     Show what would be done
  -h, --help        Show this help

Examples:
  pwt create TICKET-1234                        # no description
  pwt create TICKET-1234 "auth login bug"       # with description
  pwt create TICKET-1234 develop "auth login"   # custom base + description
  pwt create --track origin/team/TICKET-1234
  pwt track origin/team/TICKET-1234
  pwt create TICKET-1234 --branch team/TICKET-1234 --from origin/team/TICKET-1234
```

## pwt add {#add}

```
Usage: pwt create|add <branch> [base] ["description"]

Arguments:
  branch          Branch name or ticket (e.g., TICKET-1234)
  base            Base branch (default: master)
  "description"   Quoted text with spaces is treated as description

Options:
  --from <ref>      Create from specific ref (tag, commit, branch)
  --from-current    Create from current branch
  --branch <name>   Use exact Git branch name (directory still uses <branch>)
  --track <remote/ref>
  --track-existing <remote/ref>
                    Create local branch tracking an existing remote branch
  --clone           Use git clone instead of worktree
  -e, --editor      Open in editor after creation
  -n, --dry-run     Show what would be done
  -h, --help        Show this help

Examples:
  pwt create TICKET-1234                        # no description
  pwt create TICKET-1234 "auth login bug"       # with description
  pwt create TICKET-1234 develop "auth login"   # custom base + description
  pwt create --track origin/team/TICKET-1234
  pwt track origin/team/TICKET-1234
  pwt create TICKET-1234 --branch team/TICKET-1234 --from origin/team/TICKET-1234
```

## pwt track {#track}

```
Usage: pwt track <remote-branch> [--name <worktree>] [options]

Create a pwt-managed worktree that tracks an existing remote branch.
The local branch matches the remote branch name without applying branch_prefix.

Arguments:
  remote-branch   Remote branch, e.g. origin/team/TICKET-1234

Options:
  --name <name>   Override worktree directory/metadata name
  -e, --editor    Open editor after creation
  -n, --dry-run   Show what would be done
  --clone         Use git clone instead of worktree
  -h, --help      Show this help

Examples:
  pwt track origin/team/PROJ-1234
  pwt track origin/team/fix-login-flow --name login-flow
```

## pwt adopt {#adopt}

```
Usage: pwt adopt [path]
       pwt adopt --all [dir]
       pwt setup [path]

Register an existing git worktree with pwt and run standard setup.

Arguments:
  path        Existing worktree path (default: current directory)
  --all [dir] Adopt every unregistered worktree in dir (default: worktrees_dir)

This allocates/records metadata, exports PWT_* context, runs Pwtfile setup,
runs the post-create hook, and sets the worktree as current.
```

## pwt setup {#setup}

```
Usage: pwt adopt [path]
       pwt adopt --all [dir]
       pwt setup [path]

Register an existing git worktree with pwt and run standard setup.

Arguments:
  path        Existing worktree path (default: current directory)
  --all [dir] Adopt every unregistered worktree in dir (default: worktrees_dir)

This allocates/records metadata, exports PWT_* context, runs Pwtfile setup,
runs the post-create hook, and sets the worktree as current.
```

## pwt list {#list}

```
Usage: pwt list|ls [options]

List all worktrees for the current project.

Options:
  -d, --dirty      Only show dirty worktrees
  -v, --verbose    Show detailed info (original format)
  -q, --quick      Skip network operations (faster)
  -r, --refresh    Force refresh cache
  --porcelain      Output JSON (for scripts)
  --names          Output only worktree names (for completions)
  statusline       Compact single-line for prompts

Examples:
  pwt list              # Default tabular view
  pwt list -d           # Only dirty worktrees
  pwt list --porcelain  # JSON output
  pwt list --names      # Just names (for shell completion)
```

## pwt ls {#ls}

```
Usage: pwt list|ls [options]

List all worktrees for the current project.

Options:
  -d, --dirty      Only show dirty worktrees
  -v, --verbose    Show detailed info (original format)
  -q, --quick      Skip network operations (faster)
  -r, --refresh    Force refresh cache
  --porcelain      Output JSON (for scripts)
  --names          Output only worktree names (for completions)
  statusline       Compact single-line for prompts

Examples:
  pwt list              # Default tabular view
  pwt list -d           # Only dirty worktrees
  pwt list --porcelain  # JSON output
  pwt list --names      # Just names (for shell completion)
```

## pwt tree {#tree}

```
Usage: pwt tree [--all] [--dirty] [--ports] [--short] [--refresh]

Visual tree view of worktrees - mental map of active work.

Options:
  --all, -a     Show all projects (global view)
  --dirty, -d   Show only dirty worktrees
  --ports, -p   Show port mappings
  --short, -s   One line per worktree
  --refresh, -r Recompute synchronously (skip cache)

Examples:
  pwt tree              # current project
  pwt tree --all        # all projects
  pwt tree --dirty      # only dirty worktrees
  pwt tree --ports      # show ports
```

## pwt skill {#skill}

```
Usage: pwt skill [--path] [--install [dir]]

Print the agent-facing guide to driving pwt: machine-readable
flags, exit codes, wait primitives and the worktree lifecycle.

Options:
  (none)            Print the guide to stdout
  --path            Print the file path instead
  --install [dir]   Copy the skill into dir
                    (default: ~/.claude/skills/pwt-cli)

For humans, see 'pwt help' and 'pwt help pwtfile'.
```

## pwt cd {#cd}

```
Usage: pwt cd [worktree|@|-]
       pwt cd <term>      # search by name or description
       pwt cd --select    # interactive picker (fzf)

Navigate to a worktree (outputs path for shell integration).

Arguments:
  worktree  Name of the worktree
  <term>    Search term (matches name AND description)
  @         Main app directory
  -         Previous worktree (like cd -)
  (none)    Last used worktree, or main

Options:
  --select, -s    Interactive worktree selector (fzf)

Search behavior:
  - Partial name match:  pwt cd auth
  - Description search:  pwt cd "auth login"
  - If no match found, falls back to fzf for fuzzy selection

Tip: Run 'pwt shell-init' for real cd integration.
```

## pwt use {#use}

```
Usage: pwt use <worktree> [options]

Switch the current worktree symlink.

Arguments:
  worktree     Target worktree name (supports partial match)
  @            Switch to main app

Options:
  -s, --select   Interactive picker (fzf)

Examples:
  pwt use TICKET-123     # switch by name
  pwt use 123            # partial match
  pwt use @              # switch to main app
  pwt use --select       # interactive picker
```

## pwt current {#current}

```
Usage: pwt current [options]

Show the currently active worktree.

Options:
  --name       Output only the worktree name
  --port       Output only the port number
  --branch     Output only the branch name
  --path       Output only the worktree path
  --json       Output full context as JSON
  --resolved   Show resolved symlink path

Detection order:
  1. Current directory (if inside a worktree)
  2. 'current' symlink (set via 'pwt use')

Examples:
  pwt current              # show current worktree
  pwt current --port       # get port for scripts
  pwt current --json       # full context as JSON
```

## pwt info {#info}

```
Usage: pwt info [worktree] [--porcelain]

Show detailed information about a worktree.

Arguments:
  worktree     Name of the worktree (optional if inside one)
  @            Main app
  --porcelain  Machine-readable JSON output (alias: --json)

Information shown:
  - Branch and tracking information
  - Assigned port number
  - Server status
  - Directory, mode, description, and created timestamp from metadata
  - Creation metadata
  - Git status (dirty files)

Examples:
  pwt info              # info for current worktree
  pwt info TICKET-123   # info for specific worktree
  pwt info @            # info for main app
```

## pwt show {#show}

```
Usage: pwt info [worktree] [--porcelain]

Show detailed information about a worktree.

Arguments:
  worktree     Name of the worktree (optional if inside one)
  @            Main app
  --porcelain  Machine-readable JSON output (alias: --json)

Information shown:
  - Branch and tracking information
  - Assigned port number
  - Server status
  - Directory, mode, description, and created timestamp from metadata
  - Creation metadata
  - Git status (dirty files)

Examples:
  pwt info              # info for current worktree
  pwt info TICKET-123   # info for specific worktree
  pwt info @            # info for main app
```

## pwt remove {#remove}

```
Usage: pwt remove|rm [worktree] [options]

Arguments:
  worktree        Worktree name (default: current)
  @               Not allowed (cannot remove main app)

Options:
  --with-branch     Also delete the branch (if merged)
  --force-branch    Force delete the branch (even if not merged)
  --kill-port       Kill processes using the port
  --kill-<command>  Run Pwtfile <command> --kill before removal
  --kill-all        Run Pwtfile server --kill and kill port processes
  -y, --yes         Skip confirmation prompts
  -h, --help        Show this help

Safety: Dirty worktrees are backed up to ~/.pwt/trash/
```

## pwt rm {#rm}

```
Usage: pwt remove|rm [worktree] [options]

Arguments:
  worktree        Worktree name (default: current)
  @               Not allowed (cannot remove main app)

Options:
  --with-branch     Also delete the branch (if merged)
  --force-branch    Force delete the branch (even if not merged)
  --kill-port       Kill processes using the port
  --kill-<command>  Run Pwtfile <command> --kill before removal
  --kill-all        Run Pwtfile server --kill and kill port processes
  -y, --yes         Skip confirmation prompts
  -h, --help        Show this help

Safety: Dirty worktrees are backed up to ~/.pwt/trash/
```

## pwt server {#server}

```
Usage: pwt server|s [worktree] [--bg] [--no-input] [pwtfile-flags...]
       pwt server wait [worktree] [--log-contains <str>] [--timeout <s>]

Start development server for a worktree.
'pwt server wait' blocks until the server is ready (see: pwt server wait --help).

Arguments:
  worktree        Worktree name (default: current worktree or symlink)

Options:
  --bg            Run server in background (daemonize)
  --count N       With --bg: spawn N instances
  --no-input      Close stdin and set PWT_AGENT=1
  -h, --help      Show this help

Detection order:
  1. Argument provided: pwt server ACME-1234-50XX
  2. Inside worktree directory
  3. Current symlink set via 'pwt use'

Server runs on port from worktree metadata (usually 50XX).
```

## pwt s {#s}

```
Usage: pwt server|s [worktree] [--bg] [--no-input] [pwtfile-flags...]
       pwt server wait [worktree] [--log-contains <str>] [--timeout <s>]

Start development server for a worktree.
'pwt server wait' blocks until the server is ready (see: pwt server wait --help).

Arguments:
  worktree        Worktree name (default: current worktree or symlink)

Options:
  --bg            Run server in background (daemonize)
  --count N       With --bg: spawn N instances
  --no-input      Close stdin and set PWT_AGENT=1
  -h, --help      Show this help

Detection order:
  1. Argument provided: pwt server ACME-1234-50XX
  2. Inside worktree directory
  3. Current symlink set via 'pwt use'

Server runs on port from worktree metadata (usually 50XX).
```

## pwt gateway {#gateway}

```
Usage: pwt gateway <command> [args]

Manage a stable per-project gateway URL that forwards to a worktree server.

Commands:
  init --port <port> [--host <host>]
                              Configure gateway port and public host
  up [--port <port>] [--host <host>]
                              Start gateway proxy daemon
  down                      Stop gateway proxy
  start                     Alias for up
  stop                      Alias for down
  restart                   Restart gateway proxy
  status [--json]           Show gateway status
  use <worktree|@> [-- ...] Point gateway at a worktree; auto-starts server if needed
  url                       Print gateway URL
  logs [-f]                 Show gateway logs
```

## pwt servers {#servers}

```
Usage: pwt servers [--all] [--json]

Show development server status for the current project.

Options:
  --all, -a   Include stopped worktrees
  --json      Output machine-readable JSON
  -h, --help  Show this help
```

## pwt run {#run}

```
Usage: pwt run [worktree] <command...>

Run a command in a worktree without changing directory.

Arguments:
  worktree   Target worktree (@ for main, optional)
  command    Command to run in the worktree

If worktree is omitted, runs in current worktree or main.

Examples:
  pwt run TICKET-123 ./scripts/test    # in specific worktree
  pwt run @ git status           # in main app
  pwt run ./scripts/test         # in current/main
```

## pwt for-each {#for-each}

```
Usage: pwt for-each <command...>

Run a command in all worktrees.

Arguments:
  command    Command to run in each worktree

Notes:
  - If command is a Pwtfile function, runs it via Pwtfile
  - Runs in the main checkout (@) first, then in every worktree
  - Exits non-zero and lists the worktrees where the command failed

Examples:
  pwt for-each git status
  pwt for-each ./scripts/test
  pwt for-each migrate      # Runs Pwtfile migrate()
```

## pwt diff {#diff}

```
Usage: pwt diff <worktree1> [worktree2]

Show file differences between worktrees.

Arguments:
  worktree1  First worktree to compare
  worktree2  Second worktree (default: @ for main app)

Examples:
  pwt diff TICKET-123         # Compare TICKET-123 vs main
  pwt diff TICKET-123 @       # Same as above
  pwt diff TICKET-123 TICKET-456  # Compare two worktrees
```

## pwt repair {#repair}

```
Usage: pwt repair|fix [worktree]

Run repair hooks on worktrees.

Arguments:
  worktree   Specific worktree to repair (optional)
             If omitted, repairs all worktrees

Runs the 'repair' function from Pwtfile and any repair hooks.
Useful after config changes or dependency updates.

Examples:
  pwt repair               # repair all worktrees
  pwt repair TICKET-123    # repair specific worktree
```

## pwt fix {#fix}

```
Usage: pwt repair|fix [worktree]

Run repair hooks on worktrees.

Arguments:
  worktree   Specific worktree to repair (optional)
             If omitted, repairs all worktrees

Runs the 'repair' function from Pwtfile and any repair hooks.
Useful after config changes or dependency updates.

Examples:
  pwt repair               # repair all worktrees
  pwt repair TICKET-123    # repair specific worktree
```

## pwt auto-remove {#auto-remove}

```
Usage: pwt auto-remove|cleanup [target] [options]

Safely remove worktrees that have been merged into target branch.

Arguments:
  target          Target branch to check merges against (default: current)

Options:
  --execute, -y   Actually remove (default is dry-run)
  --dry-run, -n   Preview what would be removed (default)
  -h, --help      Show this help

Safety:
  - Dry-run by default (shows what would be removed)
  - Dirty worktrees backed up to ~/.pwt/trash/
  - Requires --execute for non-interactive use
```

## pwt cleanup {#cleanup}

```
Usage: pwt auto-remove|cleanup [target] [options]

Safely remove worktrees that have been merged into target branch.

Arguments:
  target          Target branch to check merges against (default: current)

Options:
  --execute, -y   Actually remove (default is dry-run)
  --dry-run, -n   Preview what would be removed (default)
  -h, --help      Show this help

Safety:
  - Dry-run by default (shows what would be removed)
  - Dirty worktrees backed up to ~/.pwt/trash/
  - Requires --execute for non-interactive use
```

## pwt restore {#restore}

```
Usage: pwt [project] restore [backup] [worktree]

  pwt restore                   List available backups
  pwt restore list              List available backups
  pwt restore <backup>          Recreate worktree and apply backup
  pwt restore <backup> <wt>     Apply backup to existing worktree

Backups are created automatically when removing dirty worktrees.
Location: ~/.pwt/trash/
```

## pwt fix-port {#fix-port}

```
Usage: pwt fix-port [worktree]

Resolve port conflicts for a worktree.

Arguments:
  worktree   Target worktree (optional if inside one)

When a port conflict is detected, offers:
  - Kill the process using the port
  - Reallocate to a new port

Examples:
  pwt fix-port              # fix port for current worktree
  pwt fix-port TICKET-123   # fix port for specific worktree
```

## pwt doctor {#doctor}

```
Usage: pwt doctor

Check system health and pwt configuration.

Checks performed:
  - Required tools (git)
  - Optional tools (jq, lsof, fzf)
  - PWT directory structure
  - Leftover legacy state backups (*.v1.bak)
  - Project configurations
  - Worktree integrity
```

## pwt state {#state}

```
Usage: pwt state [--json]
       pwt state migrate [--status|--check|--verify]

Emit a versioned JSON snapshot of all pwt state: projects,
worktrees (with metadata) and background jobs.

Subcommands:
  migrate    Inspect/apply state schema migrations
             (see docs/migrations/)

Consumers that prefer reading files directly can watch
$PWT_DIR (state-version, events.log, projects/, state/, jobs/)
as described in docs/state-v2-contract.md.
```

## pwt meta {#meta}

```
Usage: pwt meta [command] [args]
       pwt meta "text with spaces"   (set description on current worktree)
       pwt meta <key> [value]        (get/set field on current worktree)

Manage worktree metadata - descriptions, ports, and custom fields.
Metadata helps you find and identify worktrees across pwt commands.

COMMANDS:
  list                           List all metadata (default)
  show <worktree>                Show metadata for one worktree
  set <worktree> <field> <value> Set a field on any worktree
  unset [worktree] <field>       Remove a custom field (phase, reviewer, ...)
                                 Structural fields (port, path, ...) refused
  import                         Import existing worktrees

SHORTCUT (from inside a worktree - targets the worktree you are IN):
  pwt meta "text with spaces"    Set description (spaces = description)
  pwt meta <key>                 Get a field
  pwt meta <key> <value>         Set a field
  pwt meta unset <key>           Remove a field

FIELDS:
  description    Free text describing the worktree purpose
  port           Port number for dev servers (auto-allocated)
  marker         Visual marker for lists (emoji or text)
  <custom>       Any custom field you want (e.g., env, reviewer)

═══════════════════════════════════════════════════════════════════════
WHERE METADATA APPEARS
═══════════════════════════════════════════════════════════════════════

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt list                                                        │
  │ Shows description and port in the Meta column                   │
  ├─────────────────────────────────────────────────────────────────┤
  │ Worktree       Branch              Status   Meta                │
  │ ─────────────────────────────────────────────────────────────── │
  │ TICKET-123     fix/TICKET-123      ✓ clean  port=3001           │
  │                                             description=auth bug│
  │ TICKET-456     feat/TICKET-456     ● dirty  port=3002           │
  │                                             description=new API │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt select                                                      │
  │ Shows port and description in the fzf picker                    │
  ├─────────────────────────────────────────────────────────────────┤
  │ TICKET-123  fix/TICKET-123   :3001  ·  auth bug                 │
  │ TICKET-456  feat/TICKET-456  :3002  ·  new API                  │
  │ @           main             ·      ·  main app                 │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt info TICKET-123                                             │
  │ Shows all metadata fields                                       │
  ├─────────────────────────────────────────────────────────────────┤
  │ Worktree: TICKET-123                                            │
  │ Branch:   fix/TICKET-123                                        │
  │ Port:     3001                                                  │
  │ Desc:     auth bug                                              │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt cd <search>                                                 │
  │ Searches BOTH name AND description (case-insensitive)           │
  ├─────────────────────────────────────────────────────────────────┤
  │ $ pwt cd auth            # partial match                        │
  │ $ pwt cd "login bug"     # multi-word search                    │
  │ $ pwt cd "au bug"        # no match? fzf does fuzzy search      │
  │                                                                 │
  │ No match or multiple? Opens fzf for fuzzy selection             │
  └─────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════
EXAMPLES
═══════════════════════════════════════════════════════════════════════

  Setting description (quickest - text with spaces = description):
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta "fixing login auth bug"                              │
  │ ✓ TICKET-123.description = fixing login auth bug                │
  └─────────────────────────────────────────────────────────────────┘

  Setting description (explicit key):
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta description "fixing login auth bug"                  │
  │ ✓ TICKET-123.description = fixing login auth bug                │
  └─────────────────────────────────────────────────────────────────┘

  Setting description (on any worktree, from anywhere):
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta set TICKET-123 description "fixing login auth bug"   │
  │ ✓ Updated TICKET-123.description = fixing login auth bug        │
  └─────────────────────────────────────────────────────────────────┘

  Getting a field value:
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta port                                                 │
  │ 3001                                                            │
  └─────────────────────────────────────────────────────────────────┘

  Viewing all metadata:
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta show TICKET-123                                      │
  │ {                                                               │
  │   "port": 3001,                                                 │
  │   "description": "fixing login auth bug",                       │
  │   "branch": "fix/TICKET-123",                                   │
  │   "created_at": "2024-01-15T10:30:00"                           │
  │ }                                                               │
  └─────────────────────────────────────────────────────────────────┘

  Adding custom fields:
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta set TICKET-123 reviewer "@john"                      │
  │ $ pwt meta set TICKET-123 env staging                           │
  │ # Custom fields show in pwt list and pwt info                   │
  └─────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════
WORKFLOW TIPS
═══════════════════════════════════════════════════════════════════════

  Description flows naturally through the entire workflow:

     # 1. Create with description
     $ pwt create TICKET-123 "auth: fix session timeout"

     # 2. Or set later (from inside worktree)
     $ pwt meta "auth: fix session timeout"

     # 3. Find by description
     $ pwt cd timeout           # partial match
     $ pwt cd "session timeout" # multi-word
     $ pwt cd "ses time"        # no match? fzf fuzzy search

     # 4. See in lists
     $ pwt list                 # Meta column shows description
     $ pwt select               # fzf picker shows description
```

## pwt m {#m}

```
Usage: pwt meta [command] [args]
       pwt meta "text with spaces"   (set description on current worktree)
       pwt meta <key> [value]        (get/set field on current worktree)

Manage worktree metadata - descriptions, ports, and custom fields.
Metadata helps you find and identify worktrees across pwt commands.

COMMANDS:
  list                           List all metadata (default)
  show <worktree>                Show metadata for one worktree
  set <worktree> <field> <value> Set a field on any worktree
  unset [worktree] <field>       Remove a custom field (phase, reviewer, ...)
                                 Structural fields (port, path, ...) refused
  import                         Import existing worktrees

SHORTCUT (from inside a worktree - targets the worktree you are IN):
  pwt meta "text with spaces"    Set description (spaces = description)
  pwt meta <key>                 Get a field
  pwt meta <key> <value>         Set a field
  pwt meta unset <key>           Remove a field

FIELDS:
  description    Free text describing the worktree purpose
  port           Port number for dev servers (auto-allocated)
  marker         Visual marker for lists (emoji or text)
  <custom>       Any custom field you want (e.g., env, reviewer)

═══════════════════════════════════════════════════════════════════════
WHERE METADATA APPEARS
═══════════════════════════════════════════════════════════════════════

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt list                                                        │
  │ Shows description and port in the Meta column                   │
  ├─────────────────────────────────────────────────────────────────┤
  │ Worktree       Branch              Status   Meta                │
  │ ─────────────────────────────────────────────────────────────── │
  │ TICKET-123     fix/TICKET-123      ✓ clean  port=3001           │
  │                                             description=auth bug│
  │ TICKET-456     feat/TICKET-456     ● dirty  port=3002           │
  │                                             description=new API │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt select                                                      │
  │ Shows port and description in the fzf picker                    │
  ├─────────────────────────────────────────────────────────────────┤
  │ TICKET-123  fix/TICKET-123   :3001  ·  auth bug                 │
  │ TICKET-456  feat/TICKET-456  :3002  ·  new API                  │
  │ @           main             ·      ·  main app                 │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt info TICKET-123                                             │
  │ Shows all metadata fields                                       │
  ├─────────────────────────────────────────────────────────────────┤
  │ Worktree: TICKET-123                                            │
  │ Branch:   fix/TICKET-123                                        │
  │ Port:     3001                                                  │
  │ Desc:     auth bug                                              │
  └─────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────┐
  │ pwt cd <search>                                                 │
  │ Searches BOTH name AND description (case-insensitive)           │
  ├─────────────────────────────────────────────────────────────────┤
  │ $ pwt cd auth            # partial match                        │
  │ $ pwt cd "login bug"     # multi-word search                    │
  │ $ pwt cd "au bug"        # no match? fzf does fuzzy search      │
  │                                                                 │
  │ No match or multiple? Opens fzf for fuzzy selection             │
  └─────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════
EXAMPLES
═══════════════════════════════════════════════════════════════════════

  Setting description (quickest - text with spaces = description):
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta "fixing login auth bug"                              │
  │ ✓ TICKET-123.description = fixing login auth bug                │
  └─────────────────────────────────────────────────────────────────┘

  Setting description (explicit key):
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta description "fixing login auth bug"                  │
  │ ✓ TICKET-123.description = fixing login auth bug                │
  └─────────────────────────────────────────────────────────────────┘

  Setting description (on any worktree, from anywhere):
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta set TICKET-123 description "fixing login auth bug"   │
  │ ✓ Updated TICKET-123.description = fixing login auth bug        │
  └─────────────────────────────────────────────────────────────────┘

  Getting a field value:
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta port                                                 │
  │ 3001                                                            │
  └─────────────────────────────────────────────────────────────────┘

  Viewing all metadata:
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta show TICKET-123                                      │
  │ {                                                               │
  │   "port": 3001,                                                 │
  │   "description": "fixing login auth bug",                       │
  │   "branch": "fix/TICKET-123",                                   │
  │   "created_at": "2024-01-15T10:30:00"                           │
  │ }                                                               │
  └─────────────────────────────────────────────────────────────────┘

  Adding custom fields:
  ┌─────────────────────────────────────────────────────────────────┐
  │ $ pwt meta set TICKET-123 reviewer "@john"                      │
  │ $ pwt meta set TICKET-123 env staging                           │
  │ # Custom fields show in pwt list and pwt info                   │
  └─────────────────────────────────────────────────────────────────┘

═══════════════════════════════════════════════════════════════════════
WORKFLOW TIPS
═══════════════════════════════════════════════════════════════════════

  Description flows naturally through the entire workflow:

     # 1. Create with description
     $ pwt create TICKET-123 "auth: fix session timeout"

     # 2. Or set later (from inside worktree)
     $ pwt meta "auth: fix session timeout"

     # 3. Find by description
     $ pwt cd timeout           # partial match
     $ pwt cd "session timeout" # multi-word
     $ pwt cd "ses time"        # no match? fzf fuzzy search

     # 4. See in lists
     $ pwt list                 # Meta column shows description
     $ pwt select               # fzf picker shows description
```

## pwt project {#project}

```
Usage: pwt project [command] [args]

Manage project configurations.

Commands:
  list                           List all configured projects (default)
  init <name>                    Initialize a new project config
  show <name>                    Show project config and hooks
  set <name> <key> <value>       Update project config value
  path <name>                    Print project config directory path
  alias <name> [alias|--clear]   Get/set/clear project alias
  validate                       Validate current project setup

Options:
  -h, --help, help    Show this help

Config location: ~/.pwt/projects/<project>/config
Hooks location: ~/.pwt/projects/<project>/hooks/
```

## pwt config {#config}

```
Usage: pwt config [key] [value]

View or set project configuration.

Commands:
  show                 Show all settings (default)
  <key>                Show value for key
  <key> <value>        Set value for key

Keys:
  main_app       - Path to main project
  worktrees_dir  - Path to worktrees directory
  branch_prefix  - Prefix for branches (e.g., user/)
  base_port      - Base port for allocation (default: 5000)
  gateway_port   - Stable gateway proxy port
  gateway_host   - Public gateway URL host
  workspace_link - Stable symlink kept pointing at the current worktree (for editors)

Options:
  -h, --help, help    Show this help

Config location: ~/.pwt/projects/<project>/config
```

## pwt port {#port}

```
Usage: pwt port [worktree]

Get the port number for a worktree.

Arguments:
  worktree   Target worktree (optional if inside one)

Outputs just the port number, useful in scripts:
  curl http://localhost:$(pwt port)

Examples:
  pwt port               # port for current worktree
  pwt port TICKET-123    # port for specific worktree
```

## pwt plugin {#plugin}

```
Usage: pwt plugin <action>

Manage pwt plugins - extend pwt with custom commands.

Actions:
  list              List installed plugins
  install <source>  Install plugin from file or URL
  remove <name>     Remove user plugin
  create <name>     Create new plugin from template
  path              Show plugin directories

Plugin Locations:
  User plugins:   ~/.pwt/plugins/         (writable, highest priority)
  Homebrew:       $(brew --prefix)/share/pwt/plugins/
  npm:            <prefix>/share/pwt/plugins/

User plugins override system plugins with the same name.

Plugin Structure:
  Plugins are executable scripts named pwt-<command>
  Invoked as 'pwt <command>'

Environment Variables (available to plugins):
  PWT_PROJECT        Current project name
  PWT_MAIN_APP       Main app directory
  PWT_WORKTREES_DIR  Worktrees directory
  PWT_WORKTREE       Current worktree name
  PWT_PORT           Current worktree port
  PWT_BRANCH         Current worktree branch

Examples:
  pwt plugin list
  pwt plugin create github
  pwt plugin install ./my-plugin.sh
  pwt plugin remove github
```

## pwt step {#step}

```
Usage: pwt step <name> [args...]

Run a single step from the project Pwtfile.

Arguments:
  name    Step name (without step_ prefix)
  args    Passed to the function as "$1", "$2", ... and
          as raw "$PWT_ARGS"

A step that setup() calls with arguments needs the same
arguments here. Under "set -u" a missing one fails with
"$1: unbound variable" - the step is asking for input,
it is not a pwt error.

Examples:
  pwt step install          # run step_install()
  pwt step seed --fresh     # run step_seed() with args
  pwt step setup_dbs _wt42  # step that requires a positional
  pwt steps                 # list available steps
```

## pwt alias {#alias}

```
Usage: pwt alias [<name>|--clear]

Set a short alias for the current project.

Arguments:
  name       New alias (must not conflict with commands)
  --clear    Remove current alias
  (none)     Show current alias

Examples:
  pwt alias            # show current alias
  pwt alias api        # set alias to 'api'
  pwt alias --clear    # remove alias

Once aliased, use it anywhere:
  pwt api list         # same as pwt my-long-project list
  pwt api cd TICKET    # same as pwt my-long-project cd TICKET
```

## pwt jobs {#jobs}

```
Usage: pwt jobs [subcommand]

Manage background jobs started with --bg.

Subcommands:
  list [--porcelain] List all jobs (default; --porcelain for JSON)
  logs <job-id> [-f] View job output (-f to follow)
  wait <id|worktree> [--timeout <s>] Block until a job finishes
  stop <job-id>     Stop a running job
  stop --all        Stop all running jobs
  clean             Remove stale job entries
  help              Show this help

wait exits 0 when the job's process is gone and prints '<id> <status>'.
Default --timeout is 600s; on timeout it exits 5.
A worktree name resolves to its running server job (then most recent job).

Examples:
  pwt server --bg              # start server in background
  pwt jobs                     # list running jobs
  pwt jobs logs abc123         # view job output
  pwt jobs logs abc123 -f      # follow job output
  pwt jobs wait abc123 --timeout 300   # block until job exits
  pwt jobs stop abc123         # stop a job
  pwt jobs stop --all          # stop all jobs
```

## pwt logs {#logs}

```
Usage: pwt logs [worktree] [-f]

Show background-job logs for a worktree: the running server job if
any, otherwise the most recent job. Defaults to the worktree you
are in (or the current symlink).

For a specific job: pwt jobs logs <job-id> [-f]
```

## pwt self {#self}

```
Usage: pwt self [use <target>]
       pwt versions          (alias for 'pwt self')

Manage which pwt installation runs when you type 'pwt'.

Commands:
  (none)         List all installations; → marks the active one
  use local      Point ~/.local/bin/pwt at this script's own checkout
  use <path>     Point at a specific checkout (repo root or bin/pwt)
  use npm        Point at the npm-installed binary
  use brew       Point at the Homebrew binary

After switching, regenerate the shell wrapper (it hardcodes the path):
  exec $SHELL    # or: eval "$(pwt shell-init)"
```

## pwt versions {#versions}

```
Usage: pwt self [use <target>]
       pwt versions          (alias for 'pwt self')

Manage which pwt installation runs when you type 'pwt'.

Commands:
  (none)         List all installations; → marks the active one
  use local      Point ~/.local/bin/pwt at this script's own checkout
  use <path>     Point at a specific checkout (repo root or bin/pwt)
  use npm        Point at the npm-installed binary
  use brew       Point at the Homebrew binary

After switching, regenerate the shell wrapper (it hardcodes the path):
  exec $SHELL    # or: eval "$(pwt shell-init)"
```

