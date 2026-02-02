# pwt - Power Worktrees fish completion
# Install: copy to ~/.config/fish/completions/pwt.fish

# Disable file completions for pwt
complete -c pwt -f

# Helper functions
function __pwt_worktrees
    pwt list --names 2>/dev/null
end

function __pwt_projects
    if test -d ~/.pwt/projects
        ls ~/.pwt/projects/ 2>/dev/null
    end
end

function __pwt_branches
    git branch -a 2>/dev/null | sed 's/^[* ]*//' | sed 's|remotes/||'
end

function __pwt_needs_command
    set -l cmd (commandline -opc)
    test (count $cmd) -eq 1
end

function __pwt_using_command
    set -l cmd (commandline -opc)
    if test (count $cmd) -gt 1
        if test $argv[1] = $cmd[2]
            return 0
        end
    end
    return 1
end

# Main commands
complete -c pwt -n __pwt_needs_command -a init -d 'Initialize project'
complete -c pwt -n __pwt_needs_command -a create -d 'Create new worktree'
complete -c pwt -n __pwt_needs_command -a add -d 'Create new worktree (alias)'
complete -c pwt -n __pwt_needs_command -a list -d 'List worktrees'
complete -c pwt -n __pwt_needs_command -a ls -d 'List worktrees'
complete -c pwt -n __pwt_needs_command -a tree -d 'Visual tree view'
complete -c pwt -n __pwt_needs_command -a status -d 'Interactive TUI dashboard'
complete -c pwt -n __pwt_needs_command -a cd -d 'Navigate to worktree'
complete -c pwt -n __pwt_needs_command -a use -d 'Set worktree as current'
complete -c pwt -n __pwt_needs_command -a current -d 'Show current worktree'
complete -c pwt -n __pwt_needs_command -a info -d 'Show worktree details'
complete -c pwt -n __pwt_needs_command -a show -d 'Show worktree details'
complete -c pwt -n __pwt_needs_command -a remove -d 'Remove worktree'
complete -c pwt -n __pwt_needs_command -a rm -d 'Remove worktree'
complete -c pwt -n __pwt_needs_command -a server -d 'Start development server'
complete -c pwt -n __pwt_needs_command -a s -d 'Start development server'
complete -c pwt -n __pwt_needs_command -a run -d 'Run command in worktree'
complete -c pwt -n __pwt_needs_command -a for-each -d 'Run in all worktrees'
complete -c pwt -n __pwt_needs_command -a editor -d 'Open in editor'
complete -c pwt -n __pwt_needs_command -a e -d 'Open in editor'
complete -c pwt -n __pwt_needs_command -a ai -d 'Start AI tool'
complete -c pwt -n __pwt_needs_command -a open -d 'Open in Finder'
complete -c pwt -n __pwt_needs_command -a diff -d 'Diff between worktrees'
complete -c pwt -n __pwt_needs_command -a copy -d 'Copy files between worktrees'
complete -c pwt -n __pwt_needs_command -a repair -d 'Repair broken worktree'
complete -c pwt -n __pwt_needs_command -a fix -d 'Repair broken worktree'
complete -c pwt -n __pwt_needs_command -a auto-remove -d 'Remove merged worktrees'
complete -c pwt -n __pwt_needs_command -a cleanup -d 'Remove merged worktrees'
complete -c pwt -n __pwt_needs_command -a restore -d 'Recover from trash'
complete -c pwt -n __pwt_needs_command -a fix-port -d 'Resolve port conflict'
complete -c pwt -n __pwt_needs_command -a doctor -d 'Check system health'
complete -c pwt -n __pwt_needs_command -a meta -d 'Manage metadata'
complete -c pwt -n __pwt_needs_command -a project -d 'Manage projects'
complete -c pwt -n __pwt_needs_command -a config -d 'Configure project'
complete -c pwt -n __pwt_needs_command -a port -d 'Get port for worktree'
complete -c pwt -n __pwt_needs_command -a plugin -d 'Manage plugins'
complete -c pwt -n __pwt_needs_command -a claude-setup -d 'Configure Claude Code'
complete -c pwt -n __pwt_needs_command -a setup-shell -d 'Install shell integration'
complete -c pwt -n __pwt_needs_command -a shell-init -d 'Output shell init code'
complete -c pwt -n __pwt_needs_command -a help -d 'Show help'
complete -c pwt -n __pwt_needs_command -a version -d 'Show version'

# Project names as commands
complete -c pwt -n __pwt_needs_command -a '(__pwt_projects)' -d 'Project'

# Worktree completions for relevant commands
complete -c pwt -n '__pwt_using_command cd' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command use' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command server' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command s' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command info' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command show' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command port' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command editor' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command e' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command ai' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command open' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command repair' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command fix' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command fix-port' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command run' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command diff' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command copy' -a '(__pwt_worktrees)' -d 'Worktree'

# Remove command with flags
complete -c pwt -n '__pwt_using_command remove' -a '(__pwt_worktrees)' -d 'Worktree'
complete -c pwt -n '__pwt_using_command remove' -l with-branch -d 'Also delete branch'
complete -c pwt -n '__pwt_using_command remove' -l force-branch -d 'Force delete branch'
complete -c pwt -n '__pwt_using_command remove' -l kill-port -d 'Kill port processes'
complete -c pwt -n '__pwt_using_command remove' -l kill-all -d 'Kill all processes'
complete -c pwt -n '__pwt_using_command remove' -s y -l yes -d 'Skip confirmation'
complete -c pwt -n '__pwt_using_command rm' -a '(__pwt_worktrees)' -d 'Worktree'

# Create command with branches
complete -c pwt -n '__pwt_using_command create' -a '(__pwt_branches)' -d 'Branch'
complete -c pwt -n '__pwt_using_command create' -l dry-run -s n -d 'Show what would be created'
complete -c pwt -n '__pwt_using_command create' -s e -l editor -d 'Open editor after'
complete -c pwt -n '__pwt_using_command create' -s a -l ai -d 'Start AI after'
complete -c pwt -n '__pwt_using_command create' -l from -d 'Create from ref'
complete -c pwt -n '__pwt_using_command create' -l from-current -d 'Create from current branch'
complete -c pwt -n '__pwt_using_command add' -a '(__pwt_branches)' -d 'Branch'

# Meta subcommands
complete -c pwt -n '__pwt_using_command meta' -a 'list show set import' -d 'Action'

# Project subcommands
complete -c pwt -n '__pwt_using_command project' -a 'list init show set path alias' -d 'Action'

# Plugin subcommands
complete -c pwt -n '__pwt_using_command plugin' -a 'list install remove create path help' -d 'Action'

# Claude-setup subcommands
complete -c pwt -n '__pwt_using_command claude-setup' -a 'install vars format preview test toggle help' -d 'Action'

# Config keys
complete -c pwt -n '__pwt_using_command config' -a 'main_app worktrees_dir branch_prefix base_port' -d 'Config key'

# Global flags
complete -c pwt -l project -d 'Specify project' -a '(__pwt_projects)'
complete -c pwt -l help -s h -d 'Show help'
complete -c pwt -l version -s v -s V -d 'Show version'
