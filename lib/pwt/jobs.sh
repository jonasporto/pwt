#!/bin/bash
# pwt jobs module - Background job management
# Manages state for background Pwtfile executions (--bg flag)
# Job records are key=value files: jobs/<id>.job (state contract v2)

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

# Path to a job record
# Usage: _job_file <job_id>
_job_file() {
	echo "$PWT_JOBS_DIR/${1}.job"
}

# Save job metadata as key=value record
# Usage: _save_job <id> <pid> <pgid> <command> <worktree> <project> <log_file>
_save_job() {
	local id="$1" pid="$2" pgid="$3" cmd="$4" wt="$5" project="$6" log="$7"
	_init_jobs_dir
	local job_file="$PWT_JOBS_DIR/${id}.job"
	local tmp="${job_file}.tmp.$$"
	{
		printf 'id=%s\n' "$(_state_escape "$id")"
		printf 'pid=%s\n' "$pid"
		printf 'pgid=%s\n' "$pgid"
		printf 'command=%s\n' "$(_state_escape "$cmd")"
		printf 'worktree=%s\n' "$(_state_escape "$wt")"
		printf 'project=%s\n' "$(_state_escape "$project")"
		printf 'log=%s\n' "$(_state_escape "$log")"
		printf 'started_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'status=running\n'
	} >"$tmp" && mv "$tmp" "$job_file"
	events_append "$project" "$wt" "job_start" "id=$id command=$cmd"
}

# Check if a job's process is still alive
# Usage: _is_job_alive <job_id>
_is_job_alive() {
	local id="$1"
	local job_file="$PWT_JOBS_DIR/${id}.job"
	[ -f "$job_file" ] || return 1
	local pid
	pid=$(state_get "$job_file" "pid")
	[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Mark a job as stopped in its record (emits job_end on the transition)
# Usage: _mark_job_stopped <job_id>
_mark_job_stopped() {
	local id="$1"
	local job_file="$PWT_JOBS_DIR/${id}.job"
	[ -f "$job_file" ] || return 0
	local status
	status=$(state_get "$job_file" "status")
	[ "$status" = "stopped" ] && return 0
	state_set "$job_file" "status" "stopped"
	local j_project j_wt j_cmd
	j_project=$(state_get "$job_file" "project")
	j_wt=$(state_get "$job_file" "worktree")
	j_cmd=$(state_get "$job_file" "command")
	events_append "$j_project" "$j_wt" "job_end" "id=$id command=$j_cmd"
	# A stopped server job is the server going away
	[ "$j_cmd" = "server" ] && events_append "$j_project" "$j_wt" "server_stop" "id=$id"
	return 0
}

# Resolve a job id from an exact id or a worktree name.
# For a worktree name: prefer the running server job, then any running job,
# then the most recent job (mirrors the pick order used by cmd_logs).
# Usage: _resolve_job_id <id-or-worktree>
_resolve_job_id() {
	local target="$1"
	if [ -f "$PWT_JOBS_DIR/${target}.job" ]; then
		echo "$target"
		return 0
	fi

	local pick="" pick_running="" pick_server=""
	local job_file j_wt j_cmd j_id j_status
	for job_file in $(ls -t "$PWT_JOBS_DIR"/*.job 2>/dev/null); do
		[ -f "$job_file" ] || continue
		j_wt=$(state_get "$job_file" "worktree")
		[ "$j_wt" = "$target" ] || continue
		j_id=$(state_get "$job_file" "id")
		j_cmd=$(state_get "$job_file" "command")
		j_status=$(state_get "$job_file" "status")
		[ -z "$pick" ] && pick="$j_id"
		if [ "$j_status" = "running" ] && _is_job_alive "$j_id"; then
			[ -z "$pick_running" ] && pick_running="$j_id"
			if [ "$j_cmd" = "server" ] && [ -z "$pick_server" ]; then
				pick_server="$j_id"
			fi
		fi
	done

	local resolved="${pick_server:-${pick_running:-$pick}}"
	[ -n "$resolved" ] || return 1
	echo "$resolved"
}

# Block until a job's process exits (or --timeout elapses)
# Usage: _wait_job <id-or-worktree> [timeout_seconds]
# Exit: 0 job finished, EXIT_NOT_FOUND unknown job, EXIT_TIMEOUT still running
_wait_job() {
	local target="${1:-}"
	local timeout="${2:-}"
	_init_jobs_dir

	if [ -z "$target" ]; then
		pwt_error "Usage: pwt jobs wait <job-id|worktree> [--timeout <seconds>]"
		return $EXIT_USAGE
	fi
	[ -z "$timeout" ] && timeout="${PWT_WAIT_TIMEOUT_DEFAULT:-600}"
	if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
		pwt_error "Invalid --timeout value: $timeout (expected seconds as integer)"
		return $EXIT_USAGE
	fi

	local id
	if ! id=$(_resolve_job_id "$target"); then
		pwt_error "Job not found: $target"
		echo "List jobs with: pwt jobs" >&2
		return $EXIT_NOT_FOUND
	fi

	# Poll every 0.5s; two ticks per second of budget
	local ticks=$((timeout * 2))
	while _is_job_alive "$id"; do
		if [ "$ticks" -le 0 ]; then
			pwt_error "Timeout: job still running after ${timeout}s: $id"
			echo "Check it with: pwt jobs logs $id" >&2
			return $EXIT_TIMEOUT
		fi
		sleep 0.5
		ticks=$((ticks - 1))
	done

	_mark_job_stopped "$id"
	local final_status
	final_status=$(state_get "$PWT_JOBS_DIR/${id}.job" "status")
	echo "$id ${final_status:-stopped}"
}

# Check for duplicate running job (same worktree + command)
# Returns job_id if found, fails otherwise
# Usage: check_duplicate_job <worktree> <command>
check_duplicate_job() {
	local wt="$1"
	local cmd="$2"
	_init_jobs_dir
	local job_file
	for job_file in "$PWT_JOBS_DIR"/*.job; do
		[ -f "$job_file" ] || continue
		local j_wt j_cmd j_id j_status
		j_wt=$(state_get "$job_file" "worktree")
		j_cmd=$(state_get "$job_file" "command")
		j_status=$(state_get "$job_file" "status")
		j_id=$(state_get "$job_file" "id")

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

	local job_file="$PWT_JOBS_DIR/${id}.job"
	if [ ! -f "$job_file" ]; then
		pwt_error "Job not found: $id"
		return $EXIT_NOT_FOUND
	fi

	local pid pgid
	pid=$(state_get "$job_file" "pid")
	pgid=$(state_get "$job_file" "pgid")

	if ! kill -0 "$pid" 2>/dev/null; then
		echo "Job already stopped: $id"
		_mark_job_stopped "$id"
		return 0
	fi

	# Wait (polling) for the pid to exit, up to ~1s
	_wait_pid_gone() {
		local p="$1" tries=20
		while [ "$tries" -gt 0 ] && kill -0 "$p" 2>/dev/null; do
			sleep 0.05
			tries=$((tries - 1))
		done
	}

	# Try killing process group first, then individual pid
	if [ -n "$pgid" ] && [ "$pgid" != "$pid" ]; then
		kill -TERM -- "-$pgid" 2>/dev/null || true
		_wait_pid_gone "$pid"
	fi

	if kill -0 "$pid" 2>/dev/null; then
		kill -TERM "$pid" 2>/dev/null || true
		_wait_pid_gone "$pid"
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
	local job_file
	for job_file in "$PWT_JOBS_DIR"/*.job; do
		[ -f "$job_file" ] || continue
		local j_id j_status
		j_id=$(state_get "$job_file" "id")
		j_status=$(state_get "$job_file" "status")
		if [ "$j_status" = "running" ] && _is_job_alive "$j_id"; then
			_stop_job "$j_id"
			count=$((count + 1))
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
	local job_file
	for job_file in "$PWT_JOBS_DIR"/*.job; do
		[ -f "$job_file" ] || continue
		local j_id j_status
		j_id=$(state_get "$job_file" "id")
		j_status=$(state_get "$job_file" "status")

		if [ "$j_status" = "running" ] && ! _is_job_alive "$j_id"; then
			_mark_job_stopped "$j_id"
			count=$((count + 1))
		elif [ "$j_status" = "stopped" ]; then
			rm -f "$job_file" "$PWT_JOBS_DIR/${j_id}.log"
			count=$((count + 1))
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

	local job_file="$PWT_JOBS_DIR/${id}.job"
	if [ ! -f "$job_file" ]; then
		pwt_error "Job not found: $id"
		return $EXIT_NOT_FOUND
	fi

	local log
	log=$(state_get "$job_file" "log")

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

# Command: pwt logs [worktree] [-f]
# Worktree-centric log viewing: picks the worktree's server job (or the most
# recent job) so nobody needs to hunt for a job id first.
cmd_logs() {
	local follow="false" target="" arg
	for arg in "$@"; do
		case "$arg" in
		-f | --follow) follow="true" ;;
		-h | --help)
			echo "Usage: pwt logs [worktree] [-f]"
			echo ""
			echo "Show background-job logs for a worktree: the running server job if"
			echo "any, otherwise the most recent job. Defaults to the worktree you"
			echo "are in (or the current symlink)."
			echo ""
			echo "For a specific job: pwt jobs logs <job-id> [-f]"
			return 0
			;;
		*) [ -z "$target" ] && target="$arg" ;;
		esac
	done
	_init_jobs_dir

	# Resolve worktree: argument → pwd → current symlink
	if [ -z "$target" ]; then
		local cur_dir=$(pwd -P)
		local resolved_wt_dir=""
		if [ -n "$WORKTREES_DIR" ] && [ -d "$WORKTREES_DIR" ]; then
			resolved_wt_dir=$(cd "$WORKTREES_DIR" && pwd -P)
		fi
		if [ -n "$resolved_wt_dir" ] && [[ "$cur_dir" == "$resolved_wt_dir"/* ]]; then
			target="${cur_dir#$resolved_wt_dir/}"
			target="${target%%/*}"
		else
			target=$(get_current_from_symlink 2>/dev/null || echo "")
		fi
	fi
	target="${target%/}"
	if [ -z "$target" ]; then
		pwt_error "Error: No worktree specified or detected"
		echo "Usage: pwt logs [worktree] [-f]" >&2
		return $EXIT_USAGE
	fi

	# Pick a job: running server > most recent running > most recent overall
	local pick="" pick_running="" pick_server="" running_list=""
	local job_file j_wt j_cmd j_id j_status
	for job_file in $(ls -t "$PWT_JOBS_DIR"/*.job 2>/dev/null); do
		[ -f "$job_file" ] || continue
		j_wt=$(state_get "$job_file" "worktree")
		[ "$j_wt" = "$target" ] || continue
		j_cmd=$(state_get "$job_file" "command")
		j_id=$(state_get "$job_file" "id")
		j_status=$(state_get "$job_file" "status")
		[ -z "$pick" ] && pick="$j_id"
		if [ "$j_status" = "running" ] && _is_job_alive "$j_id"; then
			[ -z "$pick_running" ] && pick_running="$j_id"
			if [ "$j_cmd" = "server" ] && [ -z "$pick_server" ]; then
				pick_server="$j_id"
			fi
			running_list="${running_list:+$running_list, }$j_cmd ($j_id)"
		fi
	done

	local job="${pick_server:-${pick_running:-$pick}}"
	if [ -z "$job" ]; then
		pwt_error "No jobs found for worktree: $target"
		echo "Start one with: pwt server $target --bg" >&2
		return $EXIT_NOT_FOUND
	fi

	echo -e "${BLUE}Logs:${NC} $job" >&2
	if [ -n "$running_list" ] && [[ "$running_list" == *,* ]]; then
		echo -e "${DIM}Running for $target: $running_list — pwt jobs logs <id> for a specific one${NC}" >&2
	fi
	_tail_job_log "$job" "$follow"
}

# List all jobs with formatted output
# Machine-readable job list (JSON array). The supported way for scripts,
# Pwtfiles and external consumers to enumerate jobs - reading the job files
# directly couples callers to the on-disk format.
_jobs_list_porcelain() {
	_init_jobs_dir
	local job_file first=true

	printf '['
	for job_file in "$PWT_JOBS_DIR"/*.job; do
		[ -f "$job_file" ] || continue

		local j_id j_cmd j_wt j_proj j_pid j_log j_started j_status
		j_id=$(state_get "$job_file" "id")
		j_cmd=$(state_get "$job_file" "command")
		j_wt=$(state_get "$job_file" "worktree")
		j_proj=$(state_get "$job_file" "project")
		j_pid=$(state_get "$job_file" "pid")
		j_log=$(state_get "$job_file" "log")
		j_started=$(state_get "$job_file" "started_at")
		j_status=$(state_get "$job_file" "status")

		# Advisory status: reconcile with the actual process before reporting
		if [ "$j_status" = "running" ] && ! _is_job_alive "$j_id"; then
			j_status="dead"
			_mark_job_stopped "$j_id"
		fi

		[ "$first" = true ] || printf ','
		first=false
		printf '\n  {"id":"%s","command":"%s","worktree":"%s","project":"%s","pid":%s,"log":"%s","started_at":"%s","status":"%s"}' \
			"$(json_escape "$j_id")" \
			"$(json_escape "$j_cmd")" \
			"$(json_escape "$j_wt")" \
			"$(json_escape "$j_proj")" \
			"$(json_num_or_null "$j_pid")" \
			"$(json_escape "$j_log")" \
			"$(json_escape "$j_started")" \
			"$(json_escape "$j_status")"
	done
	[ "$first" = true ] || printf '\n'
	printf ']\n'
}

_jobs_list_formatted() {
	_init_jobs_dir
	local found=false
	local job_file

	for job_file in "$PWT_JOBS_DIR"/*.job; do
		[ -f "$job_file" ] || continue

		if [ "$found" = false ]; then
			printf "%-35s %-10s %-10s %-8s %s\n" "JOB ID" "COMMAND" "WORKTREE" "PID" "STATUS"
			printf "%-35s %-10s %-10s %-8s %s\n" "------" "-------" "--------" "---" "------"
			found=true
		fi

		local j_id j_cmd j_wt j_pid j_status
		j_id=$(state_get "$job_file" "id")
		j_cmd=$(state_get "$job_file" "command")
		j_wt=$(state_get "$job_file" "worktree")
		j_pid=$(state_get "$job_file" "pid")
		j_status=$(state_get "$job_file" "status")

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
