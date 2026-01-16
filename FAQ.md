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
