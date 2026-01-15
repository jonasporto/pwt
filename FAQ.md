# pwt FAQ

## How does pwt handle dependencies across worktrees?

Each worktree is an independent checkout, so dependencies (node_modules, vendor/bundle) need to be managed. pwt offers two strategies via **Pwtfile helpers**:

### 1. Symlinks (Share Dependencies)

```bash
setup() {
    pwtfile_symlink "node_modules"   # Share with main app
    pwtfile_symlink "vendor/bundle"  # Share Ruby gems
    pwtfile_symlink ".cache"         # Share cache directories
}
```

Creates symlinks to main app's dependencies. Saves disk space and install time.

### 2. Copy (Independent Config)

```bash
setup() {
    pwtfile_copy ".env"              # Copy env file
    pwtfile_copy "config/master.key" # Copy secrets
}
```

For files that might need per-worktree customization.

### Trade-offs

| Strategy | Pros | Cons |
|----------|------|------|
| Symlink | Saves disk, instant setup | Changes affect all worktrees |
| Copy | Independent per worktree | Uses more disk, can get stale |

### When Branches Diverge

If your branch changes `package.json` or `Gemfile`, symlinked dependencies may not match. Solutions:

```bash
# Option 1: Install locally (breaks symlink, creates real dir)
cd worktree && npm install

# Option 2: Update all worktrees
pwt for-each npm install
```

---

## How do I share a worktree's port with teammates?

Use `pwtfile_hash_port` for deterministic ports based on worktree name:

```bash
# Pwtfile
server() {
    PORT=$(pwtfile_hash_port) bin/dev
}
```

Same worktree name = same port on any machine. Useful for sharing URLs.

---

## How do I run a command in all worktrees?

```bash
pwt for-each git status -s      # Check status of all
pwt for-each npm test           # Run tests in all
pwt for-each git pull           # Update all
```

---

## How do I clean up old worktrees?

```bash
# Preview what would be removed
pwt auto-remove master --dry-run

# Remove all merged worktrees
pwt auto-remove master

# Remove specific worktree + branch
pwt remove TICKET-123 --with-branch
```

---

## How do I switch between worktrees quickly?

```bash
pwt cd TICKET-123    # Go to worktree
pwt cd -             # Go back (like cd -)
pwt cd @             # Go to main app
pwt select           # Interactive picker (requires fzf)
```

---

## How do I mark a worktree's status?

```bash
pwt marker 🚧              # Mark current as WIP
pwt marker TICKET-123 ✅   # Mark as ready
pwt marker --clear         # Clear marker
pwt list                   # Shows markers in Mkr column
```

---

## How do I use pwt with multiple projects?

```bash
# Initialize each project
pwt init ~/Projects/app1
pwt init ~/Projects/app2

# Use project name or alias
pwt app1 list
pwt app2 create feature master "desc"

# Switch between projects
pwt app1 cd TICKET-1
pwt app2 cd TICKET-2
pwt cd -                   # Works across projects
```

---

## How do I run parallel tasks without merge conflicts?

**The Challenge:** You have many tasks (e.g., 100) and want to work on them in parallel phases, ensuring tasks in the same phase don't touch the same files.

### What pwt Can Do Today

**1. Detect potential conflicts before merging:**
```bash
# See which files each worktree modified
pwt for-each git diff --name-only master

# Or more detailed
pwt for-each "echo '=== FILES ===' && git diff --name-only master"
```

**2. Check for overlapping changes:**
```bash
# List all modified files across worktrees
pwt for-each git diff --name-only master 2>/dev/null | sort | uniq -d
# Files appearing twice = potential conflict
```

### What pwt Cannot Do (Yet)

| Feature | Why Hard |
|---------|----------|
| Predict which files a task will touch | Requires AI analysis of task description |
| Auto-batch tasks into conflict-free phases | Needs task→file mapping before implementation |
| Lock files across worktrees | Git doesn't support file locking |

### Recommended Workflow

**For many parallel tasks:**

```
Phase 1: Plan
├── AI analyzes all 100 tasks
├── Groups tasks by likely file overlap (same module, same feature)
└── Creates phases: [{task1, task5, task12}, {task2, task3}, ...]

Phase 2: Execute (per phase)
├── Create worktrees for phase tasks
├── Implement in parallel
├── Check for conflicts: pwt for-each git diff --name-only master | sort | uniq -d
└── Merge all before starting next phase

Phase 3: Repeat for next phase
```

**Practical tips:**

1. **Merge frequently** - Don't let branches diverge too long
2. **Small PRs** - Each task = 1 small focused PR
3. **Rebase before merge** - `pwt for-each git rebase origin/master`
4. **Feature flags** - Merge incomplete work behind flags

### Future: Could pwt Help More?

Potential features (see BACKLOG.md):

```bash
# Hypothetical future commands
pwt conflicts                    # Show file overlap between worktrees
pwt conflicts TICKET-1 TICKET-2  # Check specific pair
pwt batch-plan tasks.json        # AI-powered phase planning
```

**Reality check:** The hard part isn't detecting conflicts—it's knowing what files a task will touch BEFORE implementing it. That requires either:
- Human knowledge of the codebase
- AI analysis of task descriptions
- Learning from past similar tasks

pwt is a shell tool, not an AI orchestrator. The batching logic is better suited for a higher-level tool (like Claude Code with a planning prompt).

---

## How do I use pwt with monorepos for parallel AI agents?

**Use case:** You have a monorepo with multiple apps/packages and want AI agents working on different features in parallel across the full stack.

### Monorepo Structure

```
mymonorepo/
├── apps/
│   ├── web/          # Frontend
│   ├── api/          # Backend
│   └── mobile/       # Mobile app
├── packages/
│   ├── shared/       # Shared code
│   └── ui/           # UI components
└── package.json      # Root workspace
```

### Strategy 1: One Worktree Per Feature (Full Stack)

```bash
# Each feature gets a worktree with access to entire monorepo
pwt create FEATURE-123 master "user authentication"
pwt create FEATURE-456 master "payment integration"

# Agent 1 works on FEATURE-123 (can touch web, api, shared)
# Agent 2 works on FEATURE-456 (can touch web, api, shared)
```

**Pros:** Each agent has full context of the feature
**Cons:** Risk of conflicts if features touch same files

### Strategy 2: Partition by Package

```bash
# Group features by primary package they modify
pwt create FEATURE-123-web master "auth frontend"
pwt create FEATURE-123-api master "auth backend"

# Agent 1: Only touches apps/web
# Agent 2: Only touches apps/api
```

**Pros:** Clear boundaries, fewer conflicts
**Cons:** Cross-cutting changes need coordination

### Conflict Detection for Monorepos

```bash
# Check which packages each worktree modified
pwt for-each "git diff --name-only master | cut -d/ -f1-2 | sort -u"

# Output might show:
# === FEATURE-123 ===
# apps/web
# packages/shared
# === FEATURE-456 ===
# apps/api
# packages/shared   # ⚠️ Potential conflict!
```

### Tips for AI Agents in Monorepos

| Tip | Why |
|-----|-----|
| **Assign packages to agents** | "Agent 1 owns apps/web, Agent 2 owns apps/api" |
| **Shared packages = sequential** | If both need `packages/shared`, do one after other |
| **Merge frequently** | Don't let worktrees diverge more than a day |
| **Rebase before work** | `pwt for-each git rebase origin/master` |

### Example Workflow

```bash
# Phase 1: Backend work (Agent 1)
pwt create FEAT-123-backend master "implement API"
# Agent works on apps/api, packages/shared

# Phase 2: Frontend work (Agent 2, after Phase 1 merged)
pwt create FEAT-123-frontend master "implement UI"
# Agent works on apps/web (shared already updated)

# Or parallel if no shared overlap:
pwt create FEAT-A-api master "feature A backend"
pwt create FEAT-B-web master "feature B frontend"
# No conflict risk - different packages
```

### Monorepo-Specific Pwtfile

```bash
# Pwtfile
setup() {
    # Monorepos often have root node_modules
    pwtfile_symlink "node_modules"

    # But packages might need their own
    for pkg in apps/*/node_modules packages/*/node_modules; do
        [ -d "$MAIN_APP/$pkg" ] && pwtfile_symlink "$pkg"
    done

    pwtfile_copy ".env"
}
```

---

## How do I handle Python venvs with worktrees?

**The Problem:** Python venvs contain hardcoded absolute paths. Symlinks don't work because the venv references the original location, not the worktree.

```bash
# This DOESN'T work:
pwtfile_symlink ".venv"  # ❌ venv still points to main app paths
```

### Solution 1: Create Fresh venv Per Worktree

```bash
# Pwtfile
setup() {
    python -m venv .venv
    .venv/bin/pip install -r requirements.txt
}
```

**Pros:** Clean, isolated environment
**Cons:** Slow setup, disk space per worktree

### Solution 2: Use uv (Fast Python Package Manager)

[uv](https://github.com/astral-sh/uv) is 10-100x faster than pip:

```bash
# Pwtfile
setup() {
    uv venv
    uv pip install -r requirements.txt
}
```

**Pros:** Near-instant venv creation
**Cons:** Requires uv installation

### Solution 3: Shared Cache with uv

```bash
# Pwtfile
setup() {
    # Share download cache across worktrees
    export UV_CACHE_DIR="$MAIN_APP/.uv-cache"

    uv venv
    uv pip install -r requirements.txt
}
```

**Pros:** Fast + saves bandwidth
**Cons:** Cache can grow large

### Solution 4: pyenv + pyenv-virtualenv

```bash
# Pwtfile
setup() {
    local venv_name="${PWT_PROJECT}-${PWT_WORKTREE}"
    pyenv virtualenv 3.11.0 "$venv_name"
    pyenv local "$venv_name"
    pip install -r requirements.txt
}

teardown() {
    local venv_name="${PWT_PROJECT}-${PWT_WORKTREE}"
    pyenv virtualenv-delete -f "$venv_name"
}
```

**Pros:** Named venvs, easy to manage
**Cons:** pyenv overhead

### Solution 5: Poetry/PDM (Dependency Managers)

```bash
# Pwtfile (Poetry)
setup() {
    poetry install
}

# Pwtfile (PDM)
setup() {
    pdm install
}
```

These tools handle venv creation automatically per project.

### Comparison

| Strategy | Speed | Disk | Isolation |
|----------|-------|------|-----------|
| Fresh venv (pip) | Slow | High | Full |
| uv venv | Fast | High | Full |
| uv + shared cache | Fast | Medium | Full |
| pyenv-virtualenv | Medium | High | Full |
| Poetry/PDM | Medium | Medium | Full |

### Recommendation

```bash
# Pwtfile - Best balance of speed and simplicity
setup() {
    if command -v uv &> /dev/null; then
        uv venv && uv pip install -r requirements.txt
    else
        python -m venv .venv && .venv/bin/pip install -r requirements.txt
    fi
}
```

**Note:** Unlike `node_modules`, Python venvs cannot be symlinked. Each worktree needs its own venv, but with uv this is fast enough to not matter.

---

## Can I jump between worktrees with a dropdown/picker?

**Yes!** Use `pwt select` (requires [fzf](https://github.com/junegunn/fzf)):

```bash
pwt select              # Interactive fuzzy picker
pwt select --preview    # With diff preview panel
```

This shows all worktrees in a searchable dropdown. Press Enter to cd to the selected worktree.

**Also useful:**
```bash
pwt cd TICKET-123    # Direct navigation
pwt cd -             # Toggle between last two (like cd -)
pwt cd @             # Go to main app
```

**Install fzf:**
```bash
# macOS
brew install fzf

# Ubuntu/Debian
sudo apt install fzf
```

---

## Does pwt support git submodules?

**Short answer:** Worktrees and submodules work together, but need care.

### How It Works

When you create a worktree, git creates a new checkout of the main repo. Submodules need to be initialized separately in each worktree.

```bash
# Pwtfile
setup() {
    git submodule update --init --recursive
}
```

### Sharing Submodule Data

Submodules have their own `.git` data. You can share it:

```bash
# Pwtfile
setup() {
    # Initialize submodules (uses shared git objects)
    git submodule update --init --recursive

    # If submodules have dependencies too:
    git submodule foreach 'npm install 2>/dev/null || true'
}
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Submodules not checked out | Add `git submodule update --init` to Pwtfile setup |
| Submodule on wrong commit | `git submodule update --recursive` |
| Submodule changes lost | Commit submodule pointer before switching worktrees |

### Full Example Pwtfile

```bash
# Pwtfile for repo with submodules
setup() {
    # Initialize all submodules
    git submodule update --init --recursive

    # Copy main config
    pwtfile_copy ".env"

    # Symlink main dependencies
    pwtfile_symlink "node_modules"

    # Install submodule dependencies if needed
    git submodule foreach 'pwtfile_symlink node_modules 2>/dev/null || true'
}
```

### Gotcha: Submodule as Symlink

If you symlink a submodule directory, changes won't be isolated per worktree. Usually you want each worktree to have its own submodule checkout:

```bash
# DON'T symlink submodules themselves
pwtfile_symlink "vendor/some-submodule"  # ❌ Bad

# DO symlink their dependencies
pwtfile_symlink "vendor/some-submodule/node_modules"  # ✅ OK
```
