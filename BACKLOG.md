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
