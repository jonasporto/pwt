# pwt Backlog

Ideas for future implementation when conditions are right.

---

## Claude Code Session Integration

**Status:** Waiting for Claude Code to expose session ID via API/env var

**Idea:**
- `pwt resume [worktree]` - Resume Claude session for a worktree
- `pwt ai --save-session` - Save session ID to metadata after exiting
- Symlink plan files to worktree root as `.claude-plan`

**Problems:**
1. Session ID not accessible (no env var, no API)
2. Plan files have random names, not tied to worktrees
3. Claude already separates projects by path (worktrees have separate dirs)

**Current workaround:**
- Use `claude --resume` with session ID from `~/.claude/projects/` (manual)
- Name chats with ticket number for easier finding

**Revisit when:**
- Claude Code exposes `$CLAUDE_SESSION_ID` or similar
- Better understanding of ideal workflow emerges

**Analysis:** See `~/.claude/plans/velvet-hopping-pnueli.md`

---

## Conflict Detection Between Worktrees

**Status:** Nice to have

**Idea:**
- `pwt conflicts` - Show file overlap between all active worktrees
- `pwt conflicts TICKET-1 TICKET-2` - Check specific pair
- Useful for parallel AI agents working on same codebase

**Current workaround:**
```bash
# Check which files each worktree modified
pwt for-each git diff --name-only master 2>/dev/null | sort | uniq -d
```

**Implementation:**
```bash
cmd_conflicts() {
    local files=$(mktemp)
    for dir in "$WORKTREES_DIR"/*/; do
        name=$(basename "$dir")
        git -C "$dir" diff --name-only master 2>/dev/null | \
            sed "s|^|$name:|" >> "$files"
    done
    # Find duplicates (same file in multiple worktrees)
    cut -d: -f2 "$files" | sort | uniq -d | while read f; do
        echo "⚠️  $f modified in:"
        grep ":$f$" "$files" | cut -d: -f1 | sed 's/^/   /'
    done
    rm "$files"
}
```

---
