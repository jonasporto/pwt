#!/bin/bash
# ============================================================
# pwt gateway module
# Stable per-project gateway and server visibility
# ============================================================

[[ -n "${_PWT_GATEWAY_LOADED:-}" ]] && return 0
_PWT_GATEWAY_LOADED=1

_gateway_project_dir() {
	echo "$PROJECTS_DIR/$CURRENT_PROJECT"
}

_gateway_config_file() {
	echo "$PROJECTS_DIR/$CURRENT_PROJECT/config"
}

# Suggest a command the user actually has for finding a port's owner
_port_owner_hint() {
	local port="$1"
	if command -v lsof >/dev/null 2>&1; then
		echo "lsof -i :$port"
	elif command -v ss >/dev/null 2>&1; then
		echo "ss -lntp sport = :$port"
	elif command -v fuser >/dev/null 2>&1; then
		echo "fuser -n tcp $port"
	else
		echo "(install lsof or ss to identify the owner of port $port)"
	fi
}

_gateway_state_file() {
	echo "$(_gateway_project_dir)/gateway.state"
}

_gateway_pid_file() {
	echo "$(_gateway_project_dir)/gateway.pid"
}

_gateway_log_file() {
	echo "$(_gateway_project_dir)/gateway.log"
}

_gateway_proxy_script() {
	echo "$(_gateway_project_dir)/gateway-proxy.js"
}

_gateway_port() {
	get_project_config "$CURRENT_PROJECT" "gateway_port"
}

_gateway_host() {
	local host
	host=$(get_project_config "$CURRENT_PROJECT" "gateway_host")
	echo "${host:-localhost}"
}

_gateway_validate_host() {
	local host="$1"
	if [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || [[ "$host" =~ ^[A-Za-z0-9]$ ]]; then
		return 0
	fi

	pwt_error "Error: gateway host must be a hostname or IP without protocol, port, or path"
	return $EXIT_USAGE
}

_gateway_require_port() {
	local port
	port=$(_gateway_port)
	if ! [[ "$port" =~ ^[0-9]+$ ]]; then
		pwt_error "Error: Gateway port is not configured for project '$CURRENT_PROJECT'"
		echo "Run: pwt gateway init --port <port>"
		return $EXIT_USAGE
	fi
	echo "$port"
}

_gateway_url() {
	local port="$1"
	local host
	host=$(_gateway_host)
	echo "http://$host:$port"
}

_gateway_set_port() {
	local port="$1"
	local config_file=$(_gateway_config_file)

	if ! [[ "$port" =~ ^[0-9]+$ ]]; then
		pwt_error "Error: gateway port must be numeric"
		return $EXIT_USAGE
	fi
	# The numeric check alone let 0 and 70000 through, to fail only at bind
	if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
		pwt_error "Error: gateway port must be in 1-65535 (got: $port)"
		return $EXIT_USAGE
	fi

	state_set "$config_file" "gateway_port" "$port" && invalidate_project_index
}

_gateway_set_host() {
	local host="$1"
	local config_file=$(_gateway_config_file)

	_gateway_validate_host "$host" || return $?

	state_set "$config_file" "gateway_host" "$host"
}

_gateway_is_running() {
	local pid_file=$(_gateway_pid_file)
	[ -f "$pid_file" ] || return 1
	local pid
	pid=$(cat "$pid_file" 2>/dev/null || true)
	[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

_gateway_target_name() {
	state_get "$(_gateway_state_file)" "target"
}

_gateway_target_port() {
	state_get "$(_gateway_state_file)" "target_port"
}

_gateway_write_proxy_script() {
	local script=$(_gateway_proxy_script)
	mkdir -p "$(dirname "$script")"
	cat >"$script" <<'NODE'
#!/usr/bin/env node
const net = require("net");
const fs = require("fs");

const listenHost = process.env.PWT_GATEWAY_HOST || "127.0.0.1";
const listenPort = Number(process.env.PWT_GATEWAY_PORT || 0);
const stateFile = process.env.PWT_GATEWAY_STATE;
const project = process.env.PWT_GATEWAY_PROJECT || "project";

function httpError(socket, status, message) {
  socket.end(
    `HTTP/1.1 ${status} ${message}\r\n` +
    "Content-Type: text/plain\r\n" +
    "Connection: close\r\n" +
    `Content-Length: ${Buffer.byteLength(message + "\n")}\r\n` +
    "\r\n" +
    `${message}\n`
  );
}

function readTarget() {
  try {
    // pwt state v2: flat key=value lines (split on first "=")
    const state = {};
    for (const line of fs.readFileSync(stateFile, "utf8").split("\n")) {
      const idx = line.indexOf("=");
      if (idx > 0) state[line.slice(0, idx)] = line.slice(idx + 1);
    }
    const port = Number(state.target_port);
    if (!Number.isInteger(port) || port <= 0) return null;
    return { port, name: state.target || "" };
  } catch (_) {
    return null;
  }
}

const server = net.createServer((client) => {
  const target = readTarget();
  if (!target) {
    httpError(client, 503, "pwt gateway has no target");
    return;
  }

  const backend = net.connect({ host: "127.0.0.1", port: target.port });
  backend.once("connect", () => {
    client.pipe(backend);
    backend.pipe(client);
  });
  backend.once("error", () => {
    httpError(client, 502, `pwt gateway target ${target.name || target.port} is unavailable`);
  });
  client.once("error", () => backend.destroy());
  client.once("close", () => backend.destroy());
});

server.once("error", (error) => {
  console.error(`[pwt gateway:${project}] ${error.message}`);
  process.exit(1);
});
server.listen(listenPort, listenHost, () => {
  console.log(`[pwt gateway:${project}] listening on ${listenHost}:${listenPort}`);
});

process.on("SIGTERM", () => server.close(() => process.exit(0)));
process.on("SIGINT", () => server.close(() => process.exit(0)));
NODE
	chmod +x "$script"
}

_gateway_start() {
	local port="$1"

	if _gateway_is_running; then
		return 0
	fi
	# Our gateway is not running, so anything listening on the port is another
	# process — spawning would EADDRINUSE and traffic would hit the wrong server.
	if _gateway_port_listening "$port"; then
		pwt_error "Error: Gateway port $port is already in use by another process"
		echo "  Find the owner with: $(_port_owner_hint "$port")" >&2
		return $EXIT_ERROR
	fi
	if ! command -v node >/dev/null 2>&1; then
		pwt_error "Error: node is required for pwt gateway"
		return $EXIT_DEPENDENCY
	fi

	local project_dir=$(_gateway_project_dir)
	local pid_file=$(_gateway_pid_file)
	local log_file=$(_gateway_log_file)
	local state_file=$(_gateway_state_file)
	local script=$(_gateway_proxy_script)

	mkdir -p "$project_dir"
	[ -f "$state_file" ] || : >"$state_file"
	_gateway_write_proxy_script

	# Same perl daemonizer as _run_pwtfile_bg: node's spawn() only controls
	# fds 0-2, so a detached child keeps every inherited fd above stderr open
	# (kcov's bash-trace pipe, caller pipes). kcov then waits on that pipe
	# forever after pwt exits, hanging the coverage run on the first gateway
	# test. Closing 3..max before exec'ing node removes the whole class.
	local pid
	pid=$(
		PWT_GATEWAY_HOST="127.0.0.1" \
			PWT_GATEWAY_PORT="$port" \
			PWT_GATEWAY_STATE="$state_file" \
			PWT_GATEWAY_PROJECT="$CURRENT_PROJECT" \
			perl -e '
			use POSIX qw(setsid);
			my ($script, $log) = @ARGV;
			my $pid = fork();
			if ($pid == 0) {
				setsid();
				open(STDIN, "<", "/dev/null");
				open(STDOUT, ">>", $log);
				open(STDERR, ">&STDOUT");
				my $max = POSIX::sysconf(&POSIX::_SC_OPEN_MAX) || 256;
				$max = 4096 if $max > 4096 || $max < 0;
				POSIX::close($_) for 3 .. $max;
				exec("node", $script) or die "exec failed: $!";
			}
			print "$pid\n";
		' "$script" "$log_file"
	)
	if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
		pwt_error "Error: Gateway failed to spawn"
		return $EXIT_ERROR
	fi
	echo "$pid" >"$pid_file"

	# Poll until the proxy listens or the process dies — no fixed sleep, so
	# 'gateway up'/'gateway use' return as soon as the port is live (~50-100ms)
	local waited_ms=0
	local max_wait_ms=$((${PWT_GATEWAY_WAIT_SECONDS:-30} * 1000))
	while ! _gateway_port_listening "$port"; do
		if ! kill -0 "$pid" 2>/dev/null; then
			rm -f "$pid_file"
			pwt_error "Error: Gateway failed to start"
			tail -20 "$log_file" 2>/dev/null || true
			return $EXIT_ERROR
		fi
		if [ "$waited_ms" -ge "$max_wait_ms" ]; then
			kill -TERM "$pid" 2>/dev/null || true
			rm -f "$pid_file"
			pwt_error "Error: Gateway did not start listening on port $port"
			tail -20 "$log_file" 2>/dev/null || true
			return $EXIT_ERROR
		fi
		sleep 0.05
		waited_ms=$((waited_ms + 50))
	done
}

_gateway_stop() {
	local pid_file=$(_gateway_pid_file)
	if ! _gateway_is_running; then
		rm -f "$pid_file"
		echo "Gateway is not running"
		return 0
	fi

	local pid
	pid=$(cat "$pid_file")
	kill -TERM "$pid" 2>/dev/null || true
	# Poll up to 0.5s for graceful exit before escalating to SIGKILL
	local tries=10
	while [ "$tries" -gt 0 ] && kill -0 "$pid" 2>/dev/null; do
		sleep 0.05
		tries=$((tries - 1))
	done
	if kill -0 "$pid" 2>/dev/null; then
		kill -9 "$pid" 2>/dev/null || true
	fi
	rm -f "$pid_file"
	echo "Gateway stopped"
}

_gateway_resolve_target() {
	local target="$1"
	local name path port branch

	if [ -z "$target" ]; then
		pwt_error "Error: Worktree target required"
		return $EXIT_USAGE
	fi

	if [ "$target" = "@" ]; then
		name="@"
		path="$MAIN_APP"
		port="${BASE_PORT:-5000}"
		branch=$(git -C "$MAIN_APP" branch --show-current 2>/dev/null || echo "")
	else
		path=$(resolve_worktree_path "$target" 2>/dev/null || true)
		if [ -z "$path" ] || [ ! -d "$path" ]; then
			pwt_error "Error: Worktree not found: $target"
			return $EXIT_NOT_FOUND
		fi
		name=$(basename "$path")
		port=$(get_metadata "$name" "port")
		branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
	fi

	if ! [[ "$port" =~ ^[0-9]+$ ]]; then
		pwt_error "Error: No numeric port found for worktree: $name"
		return $EXIT_USAGE
	fi

	printf '%s\t%s\t%s\t%s\n' "$name" "$path" "$port" "$branch"
}

_gateway_wait_for_port() {
	local port="$1"
	local seconds="${PWT_GATEWAY_WAIT_SECONDS:-30}"
	local attempts=$((seconds * 20))
	[ "$attempts" -lt 1 ] && attempts=1

	while [ "$attempts" -gt 0 ]; do
		if _gateway_port_listening "$port"; then
			return 0
		fi
		sleep 0.05
		attempts=$((attempts - 1))
	done
	return 1
}

_gateway_port_listening() {
	local port="$1"
	[ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]] || return 1
	if has_lsof; then
		[ -n "$(get_pids_on_port "$port")" ] && ! port_is_system "$port"
		return $?
	fi
	(echo >"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1
}

_gateway_save_target() {
	local name="$1"
	local path="$2"
	local port="$3"
	local branch="$4"
	local state_file=$(_gateway_state_file)

	mkdir -p "$(dirname "$state_file")"
	local tmp="${state_file}.tmp.$$"
	{
		printf 'project=%s\n' "$(_state_escape "$CURRENT_PROJECT")"
		printf 'target=%s\n' "$(_state_escape "$name")"
		printf 'target_path=%s\n' "$(_state_escape "$path")"
		printf 'target_port=%s\n' "$port"
		printf 'branch=%s\n' "$(_state_escape "$branch")"
		printf 'updated_at=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
	} >"$tmp" && mv "$tmp" "$state_file"
}

_gateway_use() {
	local target="$1"
	shift || true
	local server_args=()

	if [ "${1:-}" = "--" ]; then
		shift
		server_args=("$@")
	elif [ "$#" -gt 0 ]; then
		server_args=("$@")
	fi

	local gateway_port
	gateway_port=$(_gateway_require_port) || return $?

	local resolved
	resolved=$(_gateway_resolve_target "$target") || return $?
	local name path port branch
	IFS=$'\t' read -r name path port branch <<<"$resolved"

	if ! _gateway_port_listening "$port"; then
		if has_pwtfile_command "server"; then
			if [ "${#server_args[@]}" -gt 0 ]; then
				echo "Starting server for $name on port $port (flags: ${server_args[*]})..."
			else
				echo "Starting server for $name on port $port with DEFAULT flags"
				echo "  (pass Pwtfile flags through: pwt gateway use $name -- --worker)"
			fi
			local old_bg="$PWT_BG"
			local old_no_input="$PWT_NO_INPUT"
			PWT_BG=true
			PWT_NO_INPUT=true
			local server_status=0
			if [ "${#server_args[@]}" -gt 0 ]; then
				cmd_server "$name" "${server_args[@]}" || server_status=$?
			else
				cmd_server "$name" || server_status=$?
			fi
			if [ "$server_status" -ne 0 ]; then
				PWT_BG="$old_bg"
				PWT_NO_INPUT="$old_no_input"
				return "$server_status"
			fi
			PWT_BG="$old_bg"
			PWT_NO_INPUT="$old_no_input"
			if ! _gateway_wait_for_port "$port"; then
				pwt_error "Error: Server for $name did not start listening on port $port"
				return $EXIT_ERROR
			fi
		else
			pwt_error "Error: Target port $port is not listening and no Pwtfile server command is configured"
			return $EXIT_USAGE
		fi
	fi

	_gateway_start "$gateway_port" || return $?
	_gateway_save_target "$name" "$path" "$port" "$branch"

	echo "Gateway target: $name -> 127.0.0.1:$port"
	echo "Gateway URL:    $(_gateway_url "$gateway_port")"
}

_gateway_status() {
	local json=false
	[ "${1:-}" = "--json" ] && json=true

	local port
	port=$(_gateway_port)
	local host
	host=$(_gateway_host)
	local running=false
	_gateway_is_running && running=true
	local target=$(_gateway_target_name)
	local target_port=$(_gateway_target_port)
	local pid=""
	[ -f "$(_gateway_pid_file)" ] && pid=$(cat "$(_gateway_pid_file)" 2>/dev/null || true)

	if [ "$json" = true ]; then
		local _configured="false" _url="null"
		if [ -n "$port" ]; then
			_configured="true"
			_url=$(json_str "http://$host:$port")
		fi
		printf '{"project":%s,"configured":%s,"port":%s,"host":%s,"url":%s,"running":%s,"pid":%s,"target":%s,"target_port":%s}\n' \
			"$(json_str "$CURRENT_PROJECT")" \
			"$_configured" \
			"$(json_num_or_null "$port")" \
			"$(json_str "$host")" \
			"$_url" \
			"$running" \
			"$(json_num_or_null "$pid")" \
			"$(json_str_or_null "$target")" \
			"$(json_num_or_null "$target_port")"
		return 0
	fi

	echo "Gateway ($CURRENT_PROJECT)"
	if [[ "$port" =~ ^[0-9]+$ ]]; then
		echo "  URL:     $(_gateway_url "$port")"
	else
		echo "  URL:     (not configured)"
	fi
	echo "  Status:  $([ "$running" = true ] && echo "running" || echo "stopped")"
	[ -n "$pid" ] && echo "  PID:     $pid"
	if [ -n "$target" ]; then
		echo "  Target:  $target :$target_port"
	else
		echo "  Target:  (none)"
	fi
}

# Snapshot of listening TCP ports with their owning pid, "port<TAB>pid" per
# line. One lsof/ss call replaces one probe per worktree (66 lsof calls cost
# ~10s of `pwt servers`); empty output means no snapshot tool, and callers
# fall back to live probes. The pid is what lets a system daemon be told
# apart from a dev server without a second pass over the ports.
_ports_pid_snapshot() {
	if has_lsof; then
		lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null |
			awk 'NR>1 { n=split($9, a, ":"); if (a[n] ~ /^[0-9]+$/) print a[n] "\t" $2 }' | sort -u
	elif command -v ss >/dev/null 2>&1; then
		# -p needs privileges for other users' sockets; an unknown owner
		# stays blank and is treated as a real server, which is the safe
		# direction (reporting it as listening, not as noise to ignore).
		ss -lntpH 2>/dev/null |
			awk '{ n = split($4, a, ":"); if (a[n] !~ /^[0-9]+$/) next
			       pid = ""
			       if (match($0, /pid=[0-9]+/)) pid = substr($0, RSTART + 4, RLENGTH - 4)
			       print a[n] "\t" pid }' | sort -u
	fi
}

# Ports only, one per line (kept for callers that do not care who owns them).
_ports_snapshot() {
	_ports_pid_snapshot | cut -f1 | sort -u
}

_ensure_ports_snapshot() {
	[ -n "${_SERVERS_PORTS_SNAPSHOT_SET:-}" ] && return 0

	local pairs pids sys_pids
	pairs=$(_ports_pid_snapshot)
	_SERVERS_PORTS_SNAPSHOT=$(printf '%s\n' "$pairs" | cut -f1 | grep -E '^[0-9]+$' | sort -u)
	_SERVERS_SYSTEM_PORTS=""

	# One ps pass classifies every listener on the machine. Doing it per
	# port would cost a fork per worktree, which is what the snapshot
	# exists to avoid.
	pids=$(printf '%s\n' "$pairs" | cut -f2 | grep -E '^[0-9]+$' | sort -u | tr '\n' ',')
	if [ -n "${pids%,}" ]; then
		sys_pids=$(ps -p "${pids%,}" -o pid=,command= 2>/dev/null |
			awk -v proc_re="$PWT_SYSTEM_PROC_RE" -v path_re="$PWT_SYSTEM_PATH_RE" '
				{ pid = $1; exe = $2
				  if (exe ~ path_re) { print pid; next }
				  n = split(exe, a, "/")
				  if (a[n] ~ proc_re) print pid }' | tr '\n' ',')
		# A port counts as system only when every listener on it is one:
		# a dev server sharing it means the port is genuinely taken.
		_SERVERS_SYSTEM_PORTS=$(printf '%s\n' "$pairs" |
			awk -F'\t' -v sys="$sys_pids" '
				# comma separated: awk -v rejects a literal newline
				BEGIN { n = split(sys, s, ",")
				        for (i = 1; i <= n; i++) if (s[i] != "") issys[s[i]] = 1 }
				$1 ~ /^[0-9]+$/ { total[$1]++; if ($2 in issys) syscount[$1]++ }
				END { for (p in total) if (syscount[p] == total[p]) print p }' | sort -u)
	fi

	_SERVERS_PORTS_SNAPSHOT_SET=1
}

# Is <port> held only by system daemons (macOS AirPlay on 5000/7000)?
_port_is_system_snapshot() {
	local port="$1"
	[ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]] || return 1
	_ensure_ports_snapshot
	if [ -n "$_SERVERS_PORTS_SNAPSHOT" ]; then
		case $'\n'"${_SERVERS_SYSTEM_PORTS:-}"$'\n' in
		*$'\n'"$port"$'\n'*) return 0 ;;
		*) return 1 ;;
		esac
	fi
	port_is_system "$port"
}

# Is <port> listening, according to the snapshot (live probe fallback)?
# A system daemon holding the port is not a server of yours, so it answers no.
_port_listening_snapshot() {
	local port="$1"
	[ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]] || return 1
	_ensure_ports_snapshot
	if [ -n "$_SERVERS_PORTS_SNAPSHOT" ]; then
		case $'\n'"$_SERVERS_PORTS_SNAPSHOT"$'\n' in
		*$'\n'"$port"$'\n'*) ! _port_is_system_snapshot "$port" ;;
		*) return 1 ;;
		esac
		return $?
	fi
	_gateway_port_listening "$port"
}

# One pass over the job files (worktree<TAB>command<TAB>id<TAB>status per
# line), instead of re-reading every job file for every worktree row.
_ensure_jobs_index() {
	[ -n "${_SERVERS_JOBS_INDEX_SET:-}" ] && return 0
	load_module jobs
	local f wt cmd id st
	_SERVERS_JOBS_INDEX=""
	for f in "${PWT_JOBS_DIR:-$PWT_DIR/jobs}"/*.job; do
		[ -f "$f" ] || continue
		wt=$(state_get "$f" "worktree")
		cmd=$(state_get "$f" "command")
		id=$(state_get "$f" "id")
		st=$(state_get "$f" "status")
		_SERVERS_JOBS_INDEX+="${wt}"$'\t'"${cmd}"$'\t'"${id}"$'\t'"${st}"$'\n'
	done
	_SERVERS_JOBS_INDEX_SET=1
}

_servers_job_status_for() {
	local name="$1"
	local status="" wt cmd id st
	_ensure_jobs_index
	while IFS=$'\t' read -r wt cmd id st; do
		[ "$wt" = "$name" ] && [ "$cmd" = "server" ] || continue
		if [ "$st" = "running" ] && _is_job_alive "$id"; then
			status="job:$id"
			break
		fi
	done <<<"${_SERVERS_JOBS_INDEX:-}"
	echo "$status"
}

_servers_print_row() {
	local name="$1"
	local path="$2"
	local port="$3"
	local branch="$4"
	local markers="$5"
	local listening="stopped"
	local job_status

	if _port_listening_snapshot "$port"; then
		listening="listening"
	fi
	job_status=$(_servers_job_status_for "$name")
	[ -z "$job_status" ] && job_status="-"

	printf "%-24s %-8s %-10s %-18s %s\n" "$name" "${port:-"-"}" "$listening" "$job_status" "$markers"
	[ -n "$branch" ] && printf "  branch: %s\n" "$branch"
	printf "  path:   %s\n" "$path"

	# Other running jobs for this worktree (workers, custom commands)
	local extra_jobs="" wt cmd id st
	_ensure_jobs_index
	while IFS=$'\t' read -r wt cmd id st; do
		[ "$wt" = "$name" ] && [ "$cmd" != "server" ] && [ -n "$cmd" ] || continue
		if [ "$st" = "running" ] && _is_job_alive "$id"; then
			extra_jobs="${extra_jobs:+$extra_jobs, }$cmd ($id)"
		fi
	done <<<"${_SERVERS_JOBS_INDEX:-}"
	[ -n "$extra_jobs" ] && printf "  jobs:   %s\n" "$extra_jobs"
	return 0
}

cmd_servers() {
	local show_all=false
	local json=false

	while [ $# -gt 0 ]; do
		case "$1" in
		--all | -a)
			show_all=true
			shift
			;;
		--json)
			json=true
			shift
			;;
		-h | --help | help)
			echo "Usage: pwt servers [--all] [--json]"
			echo ""
			echo "Show development server status for the current project."
			echo ""
			echo "Options:"
			echo "  --all, -a   Include stopped worktrees"
			echo "  --json      Output machine-readable JSON"
			echo "  -h, --help  Show this help"
			return 0
			;;
		*) shift ;;
		esac
	done

	local gateway_port=$(_gateway_port)
	local gateway_running=false
	_gateway_is_running && gateway_running=true
	local gateway_target=$(_gateway_target_name)
	local current=""
	current=$(get_current_from_symlink 2>/dev/null || true)
	local has_server=false
	has_pwtfile_command "server" && has_server=true

	if [ "$json" = true ]; then
		local rows=""
		local name path port branch listening job marker row
		while IFS=$'\t' read -r name path; do
			[ -n "$name" ] && [ -d "$path" ] || continue
			port=$(get_metadata "$name" "port")
			branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
			listening=false
			_port_listening_snapshot "$port" && listening=true
			job=$(_servers_job_status_for "$name")
			marker=""
			[ "$name" = "$gateway_target" ] && marker="${marker}gateway "
			[ "$name" = "$current" ] && marker="${marker}current "
			if [ "$show_all" = true ] || [ "$listening" = true ] || [ -n "$job" ] || [ -n "$marker" ]; then
				row=$(printf '{"name":%s,"path":%s,"port":%s,"branch":%s,"listening":%s,"job":%s,"marker":%s}' \
					"$(json_str "$name")" \
					"$(json_str "$path")" \
					"$(json_num_or_null "$port")" \
					"$(json_str "$branch")" \
					"$listening" \
					"$(json_str_or_null "$job")" \
					"$(json_str "${marker% }")")
				rows="${rows:+$rows,}$row"
			fi
		done < <(list_known_worktree_entries)
		local _gw_configured="false"
		[ -n "$gateway_port" ] && _gw_configured="true"
		printf '{"project":%s,"pwtfile_server":%s,"gateway":{"configured":%s,"port":%s,"running":%s,"target":%s},"current":%s,"servers":[%s]}\n' \
			"$(json_str "$CURRENT_PROJECT")" \
			"$has_server" \
			"$_gw_configured" \
			"$(json_num_or_null "$gateway_port")" \
			"$gateway_running" \
			"$(json_str_or_null "$gateway_target")" \
			"$(json_str_or_null "$current")" \
			"$rows"
		return 0
	fi

	echo "Servers ($CURRENT_PROJECT)"
	if [ -n "$gateway_port" ]; then
		echo "  Gateway: $(_gateway_url "$gateway_port") ($([ "$gateway_running" = true ] && echo "running" || echo "stopped"))"
		[ -n "$gateway_target" ] && echo "  Target:  $gateway_target"
	else
		echo "  Gateway: not configured (pwt gateway init --port <port>)"
	fi
	echo "  Pwtfile server: $([ "$has_server" = true ] && echo "configured" || echo "not configured")"
	[ -n "$current" ] && echo "  Current: $current"
	echo ""

	printf "%-24s %-8s %-10s %-18s %s\n" "WORKTREE" "PORT" "STATUS" "JOB" "MARKERS"
	printf "%-24s %-8s %-10s %-18s %s\n" "--------" "----" "------" "---" "-------"

	local found=false
	local name path port branch markers listening job
	while IFS=$'\t' read -r name path; do
		[ -n "$name" ] && [ -d "$path" ] || continue
		port=$(get_metadata "$name" "port")
		branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
		markers=""
		[ "$name" = "$gateway_target" ] && markers="${markers}gateway "
		[ "$name" = "$current" ] && markers="${markers}current "
		listening=false
		_port_listening_snapshot "$port" && listening=true
		job=$(_servers_job_status_for "$name")

		if [ "$show_all" = true ] || [ "$listening" = true ] || [ -n "$job" ] || [ -n "$markers" ]; then
			_servers_print_row "$name" "$path" "$port" "$branch" "${markers% }"
			found=true
		fi
	done < <(list_known_worktree_entries)

	if [ "$found" = false ]; then
		echo "(no active servers; use --all to show stopped worktrees)"
	fi
}

cmd_gateway() {
	local subcmd="${1:-status}"
	shift || true

	case "$subcmd" in
	-h | --help | help)
		echo "Usage: pwt gateway <command> [args]"
		echo ""
		echo "Manage a stable per-project gateway URL that forwards to a worktree server."
		echo ""
		echo "Commands:"
		echo "  init --port <port> [--host <host>]"
		echo "                              Configure gateway port and public host"
		echo "  up [--port <port>] [--host <host>]"
		echo "                              Start gateway proxy daemon"
		echo "  down                      Stop gateway proxy"
		echo "  start                     Alias for up"
		echo "  stop                      Alias for down"
		echo "  restart                   Restart gateway proxy"
		echo "  status [--json]           Show gateway status"
		echo "  use <worktree|@> [-- ...] Point gateway at a worktree; auto-starts server if needed"
		echo "  url                       Print gateway URL"
		echo "  logs [-f]                 Show gateway logs"
		return 0
		;;
	init)
		local port=""
		local host=""
		while [ $# -gt 0 ]; do
			case "$1" in
			--port | -p)
				port="${2:-}"
				shift 2
				;;
			--host | -H)
				host="${2:-}"
				shift 2
				;;
			*)
				port="$1"
				shift
				;;
			esac
		done
		if ! [[ "$port" =~ ^[0-9]+$ ]]; then
			pwt_error "Error: gateway init requires --port <port>"
			return $EXIT_USAGE
		fi
		# Refuse a port already owned by another process (unless it's this
		# project's own gateway already listening there)
		if _gateway_port_listening "$port"; then
			local cur_port=$(_gateway_port 2>/dev/null || echo "")
			if ! { _gateway_is_running && [ "$cur_port" = "$port" ]; }; then
				pwt_error "Error: Port $port is already in use by another process"
				echo "  Pick a free port, or find the owner with: $(_port_owner_hint "$port")" >&2
				return $EXIT_USAGE
			fi
		fi
		_gateway_set_port "$port" || return $?
		if [ -n "$host" ]; then
			_gateway_set_host "$host" || return $?
		fi
		echo "Gateway port set to $port"
		if [ -n "$host" ]; then
			echo "Gateway host set to $host"
		fi
		;;
	up | start)
		local port
		while [ $# -gt 0 ]; do
			case "$1" in
			--port | -p)
				_gateway_set_port "${2:-}" || return $?
				shift 2
				;;
			--host | -H)
				_gateway_set_host "${2:-}" || return $?
				shift 2
				;;
			*) shift ;;
			esac
		done
		port=$(_gateway_require_port) || return $?
		_gateway_start "$port"
		echo "Gateway running at $(_gateway_url "$port")"
		;;
	down | stop)
		_gateway_stop
		;;
	restart)
		_gateway_stop >/dev/null || true
		local port
		port=$(_gateway_require_port) || return $?
		_gateway_start "$port"
		echo "Gateway running at $(_gateway_url "$port")"
		;;
	status)
		_gateway_status "$@"
		;;
	use)
		_gateway_use "${1:-}" "${@:2}"
		;;
	url)
		local port
		port=$(_gateway_require_port) || return $?
		echo "$(_gateway_url "$port")"
		;;
	logs | log)
		local log_file=$(_gateway_log_file)
		[ -f "$log_file" ] || {
			echo "No gateway log found"
			return 0
		}
		if [ "${1:-}" = "-f" ] || [ "${1:-}" = "--follow" ]; then
			tail -f "$log_file"
		else
			tail -50 "$log_file"
		fi
		;;
	*)
		pwt_error "Unknown gateway command: $subcmd"
		echo "Run 'pwt gateway help' for usage"
		return $EXIT_USAGE
		;;
	esac
}
