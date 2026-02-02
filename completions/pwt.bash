# pwt - Power Worktrees bash completion
# Install: source this file or add to /etc/bash_completion.d/

_pwt_commands="init create add list ls tree status cd use current info show remove rm server s run for-each editor e ai open diff copy repair fix auto-remove cleanup restore fix-port doctor meta project config port plugin claude-setup setup-shell shell-init help version"

_pwt_meta_actions="list show set import"
_pwt_project_actions="list init show set path alias"
_pwt_plugin_actions="list install remove create path help"
_pwt_claude_actions="install vars format preview test toggle help"

_pwt_get_worktrees() {
    pwt list --names 2>/dev/null
}

_pwt_get_projects() {
    if [[ -d ~/.pwt/projects ]]; then
        ls ~/.pwt/projects/ 2>/dev/null
    fi
}

_pwt_get_branches() {
    git branch -a 2>/dev/null | sed 's/^[* ]*//' | sed 's|remotes/||'
}

_pwt() {
    local cur prev words cword
    _init_completion || return

    # Get the command (first non-option argument)
    local cmd=""
    local i
    for ((i=1; i < cword; i++)); do
        case "${words[i]}" in
            --project)
                ((i++))
                ;;
            -*)
                ;;
            *)
                if [[ -z "$cmd" ]]; then
                    cmd="${words[i]}"
                fi
                ;;
        esac
    done

    # Complete commands or projects at first position
    if [[ -z "$cmd" ]]; then
        local projects=$(_pwt_get_projects)
        COMPREPLY=($(compgen -W "$_pwt_commands $projects" -- "$cur"))
        return
    fi

    # Command-specific completions
    case "$cmd" in
        create|add)
            # First arg: branch, second: base ref
            local nargs=0
            for ((i=1; i < cword; i++)); do
                [[ "${words[i]}" != -* ]] && ((nargs++))
            done
            if [[ $nargs -le 2 ]]; then
                COMPREPLY=($(compgen -W "$(_pwt_get_branches)" -- "$cur"))
            fi
            ;;
        cd|use|server|s|info|show|port|editor|e|ai|open|repair|fix|fix-port)
            COMPREPLY=($(compgen -W "$(_pwt_get_worktrees)" -- "$cur"))
            ;;
        remove|rm)
            local flags="--with-branch --force-branch --kill-port --kill-sidekiq --kill-all -y --yes"
            COMPREPLY=($(compgen -W "$(_pwt_get_worktrees) $flags" -- "$cur"))
            ;;
        run|for-each)
            if [[ "$prev" == "run" ]] || [[ "$prev" == "for-each" ]]; then
                COMPREPLY=($(compgen -W "$(_pwt_get_worktrees)" -- "$cur"))
            fi
            ;;
        diff|copy)
            COMPREPLY=($(compgen -W "$(_pwt_get_worktrees)" -- "$cur"))
            ;;
        auto-remove|cleanup)
            COMPREPLY=($(compgen -W "$(_pwt_get_branches)" -- "$cur"))
            ;;
        meta)
            if [[ "$prev" == "meta" ]]; then
                COMPREPLY=($(compgen -W "$_pwt_meta_actions" -- "$cur"))
            elif [[ "$prev" == "show" ]] || [[ "$prev" == "set" ]]; then
                COMPREPLY=($(compgen -W "$(_pwt_get_worktrees)" -- "$cur"))
            fi
            ;;
        project)
            if [[ "$prev" == "project" ]]; then
                COMPREPLY=($(compgen -W "$_pwt_project_actions" -- "$cur"))
            elif [[ "$prev" == "show" ]] || [[ "$prev" == "set" ]] || [[ "$prev" == "path" ]] || [[ "$prev" == "alias" ]]; then
                COMPREPLY=($(compgen -W "$(_pwt_get_projects)" -- "$cur"))
            fi
            ;;
        plugin)
            if [[ "$prev" == "plugin" ]]; then
                COMPREPLY=($(compgen -W "$_pwt_plugin_actions" -- "$cur"))
            fi
            ;;
        claude-setup)
            if [[ "$prev" == "claude-setup" ]]; then
                COMPREPLY=($(compgen -W "$_pwt_claude_actions" -- "$cur"))
            fi
            ;;
        config)
            local keys="main_app worktrees_dir branch_prefix base_port"
            COMPREPLY=($(compgen -W "$keys" -- "$cur"))
            ;;
        list|ls|tree|status|doctor|pick|select|help|version)
            # These commands have optional flags, no required completions
            ;;
    esac
}

complete -F _pwt pwt
