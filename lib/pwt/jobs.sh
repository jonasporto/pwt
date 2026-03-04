#!/bin/bash
# pwt jobs module - Background job management
# Manages state for background Pwtfile executions (--bg flag)

PWT_JOBS_DIR="${PWT_DIR}/jobs"

# Initialize jobs directory
_init_jobs_dir() {
    mkdir -p "$PWT_JOBS_DIR" 2>/dev/null || true
}

# Generate a unique job ID
# Usage: _generate_job_id <worktree> <command>
_generate_job_id() {
    local worktree="$1"
    local cmd="$2"
    local ts
    ts=$(date +%s)
    echo "${worktree}-${cmd}-${ts}"
}

# Save job metadata as JSON
# Usage: _save_job <id> <pid> <pgid> <command> <worktree> <project> <log_file>
_save_job() {
    local id="$1" pid="$2" pgid="$3" cmd="$4" wt="$5" project="$6" log="$7"
    _init_jobs_dir
    cat > "$PWT_JOBS_DIR/${id}.json" << EOF
{
  "id": "$id",
  "pid": $pid,
  "pgid": $pgid,
  "command": "$cmd",
  "worktree": "$wt",
  "project": "$project",
  "log": "$log",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "running"
}
EOF
}

# Check if a job's process is still alive
# Usage: _is_job_alive <job_id>
_is_job_alive() {
    local id="$1"
    local json="$PWT_JOBS_DIR/${id}.json"
    [ -f "$json" ] || return 1
    local pid
    pid=$(grep -o '"pid": *[0-9]*' "$json" | grep -o '[0-9]*')
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Mark a job as stopped in its JSON
# Usage: _mark_job_stopped <job_id>
_mark_job_stopped() {
    local id="$1"
    local json="$PWT_JOBS_DIR/${id}.json"
    [ -f "$json" ] || return 0
    # Use a temp file for portable in-place edit
    local tmp="${json}.tmp"
    sed 's/"status": "running"/"status": "stopped"/' "$json" > "$tmp" && mv "$tmp" "$json"
}

# Check for duplicate running job (same worktree + command)
# Returns job_id if found, fails otherwise
# Usage: check_duplicate_job <worktree> <command>
check_duplicate_job() {
    local wt="$1"
    local cmd="$2"
    _init_jobs_dir
    local json_file
    for json_file in "$PWT_JOBS_DIR"/*.json; do
        [ -f "$json_file" ] || continue
        local j_wt j_cmd j_id j_status
        j_wt=$(grep -o '"worktree": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_cmd=$(grep -o '"command": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_status=$(grep -o '"status": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_id=$(grep -o '"id": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')

        if [ "$j_wt" = "$wt" ] && [ "$j_cmd" = "$cmd" ] && [ "$j_status" = "running" ]; then
            # Verify process is actually running
            if _is_job_alive "$j_id"; then
                echo "$j_id"
                return 0
            else
                # Stale entry, mark as stopped
                _mark_job_stopped "$j_id"
            fi
        fi
    done
    return 1
}

# Stop a job by ID (TERM signal to process group, fallback to pid)
# Usage: _stop_job <job_id>
_stop_job() {
    local id="$1"

    if [ -z "$id" ]; then
        pwt_error "Usage: pwt jobs stop <job_id>"
        return $EXIT_USAGE
    fi

    local json="$PWT_JOBS_DIR/${id}.json"
    if [ ! -f "$json" ]; then
        pwt_error "Job not found: $id"
        return $EXIT_NOT_FOUND
    fi

    local pid pgid
    pid=$(grep -o '"pid": *[0-9]*' "$json" | grep -o '[0-9]*')
    pgid=$(grep -o '"pgid": *[0-9]*' "$json" | grep -o '[0-9]*')

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "Job already stopped: $id"
        _mark_job_stopped "$id"
        return 0
    fi

    # Try killing process group first, then individual pid
    if [ -n "$pgid" ] && [ "$pgid" != "$pid" ]; then
        kill -TERM -- "-$pgid" 2>/dev/null || true
        sleep 1
    fi

    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
    fi

    # Force kill if still running
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi

    _mark_job_stopped "$id"
    echo -e "${GREEN}Stopped:${NC} $id"
}

# Stop all running jobs
_stop_all_jobs() {
    _init_jobs_dir
    local count=0
    local json_file
    for json_file in "$PWT_JOBS_DIR"/*.json; do
        [ -f "$json_file" ] || continue
        local j_id j_status
        j_id=$(grep -o '"id": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_status=$(grep -o '"status": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        if [ "$j_status" = "running" ] && _is_job_alive "$j_id"; then
            _stop_job "$j_id"
            ((count++))
        fi
    done
    if [ "$count" -eq 0 ]; then
        echo "No running jobs to stop"
    else
        echo "Stopped $count job(s)"
    fi
}

# Clean stale job entries (dead processes)
_clean_jobs() {
    _init_jobs_dir
    local count=0
    local json_file
    for json_file in "$PWT_JOBS_DIR"/*.json; do
        [ -f "$json_file" ] || continue
        local j_id j_status
        j_id=$(grep -o '"id": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_status=$(grep -o '"status": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')

        if [ "$j_status" = "running" ] && ! _is_job_alive "$j_id"; then
            _mark_job_stopped "$j_id"
            ((count++))
        elif [ "$j_status" = "stopped" ]; then
            rm -f "$json_file" "$PWT_JOBS_DIR/${j_id}.log"
            ((count++))
        fi
    done
    echo "Cleaned $count job(s)"
}

# Tail job log
# Usage: _tail_job_log <job_id> <follow:true|false>
_tail_job_log() {
    local id="$1"
    local follow="${2:-false}"

    if [ -z "$id" ]; then
        pwt_error "Usage: pwt jobs logs <job_id> [-f]"
        return $EXIT_USAGE
    fi

    local json="$PWT_JOBS_DIR/${id}.json"
    if [ ! -f "$json" ]; then
        pwt_error "Job not found: $id"
        return $EXIT_NOT_FOUND
    fi

    local log
    log=$(grep -o '"log": *"[^"]*"' "$json" | sed 's/"log": *"//;s/"$//')

    if [ ! -f "$log" ]; then
        pwt_error "Log file not found: $log"
        return $EXIT_NOT_FOUND
    fi

    if [ "$follow" = "true" ]; then
        tail -f "$log"
    else
        tail -50 "$log"
    fi
}

# List all jobs with formatted output
_jobs_list_formatted() {
    _init_jobs_dir
    local found=false
    local json_file

    for json_file in "$PWT_JOBS_DIR"/*.json; do
        [ -f "$json_file" ] || continue

        if [ "$found" = false ]; then
            printf "%-35s %-10s %-10s %-8s %s\n" "JOB ID" "COMMAND" "WORKTREE" "PID" "STATUS"
            printf "%-35s %-10s %-10s %-8s %s\n" "------" "-------" "--------" "---" "------"
            found=true
        fi

        local j_id j_cmd j_wt j_pid j_status
        j_id=$(grep -o '"id": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_cmd=$(grep -o '"command": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_wt=$(grep -o '"worktree": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')
        j_pid=$(grep -o '"pid": *[0-9]*' "$json_file" | grep -o '[0-9]*')
        j_status=$(grep -o '"status": *"[^"]*"' "$json_file" | sed 's/.*"\([^"]*\)"$/\1/')

        # Update status if process died
        if [ "$j_status" = "running" ] && ! _is_job_alive "$j_id"; then
            j_status="dead"
            _mark_job_stopped "$j_id"
        fi

        local color="$GREEN"
        [ "$j_status" != "running" ] && color="$DIM"

        printf "${color}%-35s %-10s %-10s %-8s %s${NC}\n" "$j_id" "$j_cmd" "$j_wt" "$j_pid" "$j_status"
    done

    if [ "$found" = false ]; then
        echo "No jobs found"
        echo ""
        echo "Start a background job with: pwt server --bg"
    fi
}
