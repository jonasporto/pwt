#!/bin/bash
# ============================================================
# pwt router module
# A stable public port per worktree, owned by a resident proxy: it wakes a
# stopped server on the first request, stops servers nobody uses, and keeps
# the number of running servers under a machine-wide cap. Optionally it
# also routes by Host name on one shared port (router.host_routing).
# ============================================================
#
# The proxy itself is lib/pwt/router.js (node, no dependencies). This file
# owns everything the proxy asks bash for: hostnames, the policy knobs, and
# the decisions that touch jobs (which server to evict, whether a server is
# idle enough to stop). Keeping naming and job control here means `pwt
# server --bg`, `pwt servers` and the router can never disagree about them.

[[ -n "${_PWT_ROUTER_LOADED:-}" ]] && return 0
_PWT_ROUTER_LOADED=1

# key<TAB>default<TAB>description, in the order `pwt router config` lists them
_ROUTER_KEYS='port_offset	10000	Public port of a worktree = its pwt port + this offset
port	7600	Port of the router itself (status page; Host routing when enabled)
listen	127.0.0.1,::1	Comma-separated addresses to bind
host_routing	false	Also route <worktree>.<project>.<domain> on the router port
domain	localhost	Base domain appended to every hostname
template	{worktree}.{project}	Hostname of a worktree, before the domain
alias_template	{alias}.{worktree}.{project}	Hostname of a Pwtfile hosts() alias
main_template	{project}	Hostname of the main app (@)
main_alias_template	{alias}.{project}	Alias hostname of the main app
scheme	http	Scheme used in PWT_URL (https behind a TLS proxy)
public_port		Port shown in PWT_URL (default: router port for http, none for https)
hold_seconds	30	How long a non-HTML request waits for a waking server
boot_timeout	120	Seconds a boot may take before it is reported failed
idle_minutes	30	Stop a routed server after this long without traffic (0 = never)
max_servers	0	Machine-wide cap on running pwt servers (0 = no cap)
expose_logs	true	Show the job log tail on the router failure page'

_router_dir() {
	echo "$PWT_DIR/router"
}

_router_pid_file() {
	echo "$PWT_DIR/router/router.pid"
}

_router_log_file() {
	echo "$PWT_DIR/router/router.log"
}

_router_activity_file() {
	echo "$PWT_DIR/router/activity"
}

_router_key_default() {
	printf '%s\n' "$_ROUTER_KEYS" | awk -F'\t' -v k="$1" '$1 == k { print $2; found = 1 } END { exit !found }'
}

# Effective value of a router key (configured, else its default)
_router_get() {
	router_config "$1" "$(_router_key_default "$1")"
}

_router_is_running() {
	local pid
	pid=$(cat "$(_router_pid_file)" 2>/dev/null || true)
	[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# The project's Pwtfile, for any project (not only the current one)
_router_project_pwtfile() {
	local project="$1" cfg main
	cfg=$(get_project_config "$project" "pwtfile")
	main=$(get_project_config "$project" "path")
	if [ -n "$cfg" ]; then
		cfg="${cfg/#\~/$HOME}"
		[[ "$cfg" != /* ]] && cfg="$main/$cfg"
		[ -f "$cfg" ] && echo "$cfg"
		return 0
	fi
	[ -n "$main" ] && [ -f "$main/Pwtfile" ] && echo "$main/Pwtfile"
	return 0
}

# Extra hostnames a project's app answers on, from its Pwtfile `hosts()`:
# one name per line ("api", "hub"), or "*" to route every label in front of
# an instance's own host to it (apps that serve <tenant>.<host>).
# Prints them space-separated.
_router_aliases() {
	local project="$1" pwtfile
	pwtfile=$(_router_project_pwtfile "$project")
	[ -n "$pwtfile" ] || return 0
	grep -qE "^hosts\s*\(\)|^function\s+hosts\b" "$pwtfile" 2>/dev/null || return 0
	(
		export PWT_PROJECT="$project"
		# User-provided file, path known only at runtime
		# shellcheck source=/dev/null
		source "$pwtfile" >/dev/null 2>&1
		hosts </dev/null 2>/dev/null
	) | awk '/^[[:space:]]*(\*|[A-Za-z0-9][A-Za-z0-9-]*)[[:space:]]*$/ { gsub(/[[:space:]]/, ""); printf "%s%s", sep, $0; sep = " " }'
}

# Every routable instance: project<TAB>worktree<TAB>port<TAB>aliases
_router_rows() {
	local pdir project main base aliases meta wt port path
	for pdir in "$PWT_PROJECTS_DIR"/*/; do
		[ -f "${pdir}config" ] || continue
		project=$(basename "$pdir")
		aliases=$(_router_aliases "$project")
		main=$(get_project_config "$project" "path")
		base=$(get_project_config "$project" "base_port")
		if [ -n "$main" ] && [ -d "$main" ]; then
			printf '%s\t@\t%s\t%s\n' "$project" "${base:-5000}" "$aliases"
		fi
		for meta in "$PWT_DIR/state/$project"/*.meta; do
			[ -f "$meta" ] || continue
			wt=$(basename "$meta" .meta)
			port=$(state_get "$meta" "port")
			path=$(state_get "$meta" "path")
			[[ "$port" =~ ^[0-9]+$ ]] && [ -d "$path" ] || continue
			printf '%s\t%s\t%s\t%s\n' "$project" "$wt" "$port" "$aliases"
		done
	done
}

# Rows in, routes out:
#   host<TAB>project<TAB>worktree<TAB>port<TAB>alias<TAB>var<TAB>public_port
# Names are slugged (lowercase, [a-z0-9-]) because worktree names are
# directory names and hostnames are not. "*" yields a "*.<host>" route.
_router_render() {
	awk -F'\t' -v OFS='\t' \
		-v domain="$(_router_get domain)" \
		-v wt_t="$(_router_get template)" -v wt_at="$(_router_get alias_template)" \
		-v main_t="$(_router_get main_template)" -v main_at="$(_router_get main_alias_template)" \
		-v offset="$(_router_get port_offset)" '
		function slug(s) {
			s = tolower(s)
			gsub(/[^a-z0-9-]/, "-", s)
			gsub(/-+/, "-", s)
			sub(/^-/, "", s)
			sub(/-$/, "", s)
			return s
		}
		function repl(t, k, v,    i, out) {
			out = ""
			while ((i = index(t, k)) > 0) {
				out = out substr(t, 1, i - 1) v
				t = substr(t, i + length(k))
			}
			return out t
		}
		function render(t, p, w, a) {
			t = repl(t, "{project}", p)
			t = repl(t, "{worktree}", w)
			t = repl(t, "{alias}", a)
			t = tolower(t)
			if (d != "") t = t "." d
			return t
		}
		BEGIN { d = tolower(domain) }
		NF >= 3 {
			pub = $3 + offset
			if ($3 + 0 <= 0 || pub > 65535) pub = ""
			p = slug($1); main = ($2 == "@")
			w = main ? "" : slug($2)
			t = main ? main_t : wt_t
			at = main ? main_at : wt_at
			host = render(t, p, w, "")
			print host, $1, $2, $3, "", "", pub
			n = split($4, al, " ")
			for (i = 1; i <= n; i++) {
				if (al[i] == "") continue
				if (al[i] == "*") { print "*." host, $1, $2, $3, "*", "", pub; continue }
				a = slug(al[i])
				v = "PWT_HOST_" toupper(a)
				gsub(/-/, "_", v)
				print render(at, p, w, a), $1, $2, $3, al[i], v, pub
			}
		}'
}

# The URL a browser uses for <host> (scheme, and the port unless implied)
_router_url() {
	local host="$1" scheme port
	scheme=$(_router_get scheme)
	port=$(router_config public_port)
	if [ -z "$port" ]; then
		[ "$scheme" = http ] && port=$(_router_get port)
	fi
	case "$scheme:$port" in
		*: | *:none | *:0 | http:80 | https:443) port="" ;;
	esac
	printf '%s://%s%s\n' "$scheme" "$host" "${port:+:$port}"
}

# Export what the router makes of one instance, for its Pwtfile:
#   PWT_PUBLIC_PORT   the stable port the router serves this worktree on
#   PWT_PUBLIC_URL    http://localhost:<PWT_PUBLIC_PORT>
# and, with router.host_routing on:
#   PWT_HOST          the instance's own host (the base for "*" tenants)
#   PWT_URL           browser URL of PWT_HOST through the router
#   PWT_HOST_<ALIAS>  one per hosts() alias (api -> PWT_HOST_API)
#   PWT_HOSTS         every host above, space-separated (allowed hosts)
#   PWT_DOMAIN        the router's base domain
# Always defined (empty when not applicable) so `set -u` Pwtfiles are safe.
# The server itself still binds PWT_PORT: the router forwards to it.
router_export_env() {
	local project="$1" wt="$2" port="${3:-}" offset host p w _port alias var pub routes
	export PWT_PUBLIC_PORT="" PWT_PUBLIC_URL=""
	export PWT_HOST="" PWT_URL="" PWT_HOSTS="" PWT_DOMAIN=""
	[ -n "$project" ] && [ -n "$wt" ] || return 0
	if [[ "$port" =~ ^[0-9]+$ ]]; then
		offset=$(_router_get port_offset)
		[[ "$offset" =~ ^[0-9]+$ ]] || offset=10000
		if [ $((port + offset)) -le 65535 ]; then
			PWT_PUBLIC_PORT=$((port + offset))
			PWT_PUBLIC_URL="http://localhost:$PWT_PUBLIC_PORT"
		fi
	fi
	[ "$(_router_get host_routing)" = true ] || return 0
	PWT_DOMAIN=$(_router_get domain)
	routes=$(printf '%s\t%s\t0\t%s\n' "$project" "$wt" "$(_router_aliases "$project")" | _router_render)
	while IFS=$'\037' read -r host p w _port alias var pub; do
		[ -n "$host" ] || continue
		if [ -z "$alias" ]; then
			PWT_HOST="$host"
			PWT_URL=$(_router_url "$host")
		elif [ -n "$var" ]; then
			export "$var=$host"
		fi
		[ "$alias" = "*" ] || PWT_HOSTS="${PWT_HOSTS:+$PWT_HOSTS }$host"
	done <<<"$(printf '%s' "$routes" | tr '\t' '\037')"
	return 0
}

# ------------------------------------------------------------
# Instances, idleness and the cap
# ------------------------------------------------------------

# Running pwt-managed server instances, one line each:
#   project<TAB>worktree<TAB>last_activity_epoch<TAB>busy(0|1)
# An instance is a worktree's `server` jobs (workers started by the same
# server() are part of it). The main app (@) is never an instance: it is
# not stopped by idleness nor counted by the cap. Busy = a request or a
# websocket in flight through the router, or any other pwt job running for
# that worktree (a test run, a setup) that stopping the server would break.
_router_instances() {
	load_module jobs
	local f id st cmd p w started servers="" others=""
	for f in "${PWT_JOBS_DIR:-$PWT_DIR/jobs}"/*.job; do
		[ -f "$f" ] || continue
		st=$(state_get "$f" "status")
		[ "$st" = running ] || continue
		id=$(state_get "$f" "id")
		_is_job_alive "$id" || continue
		cmd=$(state_get "$f" "command")
		p=$(state_get "$f" "project")
		w=$(state_get "$f" "worktree")
		if [ "$cmd" = server ]; then
			[ "$w" = "@" ] && continue
			started=$(state_get "$f" "started_epoch")
			servers+="${p}"$'\t'"${w}"$'\t'"${started:-0}"$'\n'
		else
			others+="${p}"$'\t'"${w}"$'\n'
		fi
	done
	[ -n "$servers" ] || return 0
	local activity
	activity=$(_router_activity_file)
	[ -f "$activity" ] || activity=/dev/null
	awk -F'\t' -v OFS='\t' '
		FILENAME == ARGV[1] { act[$1 FS $2] = $3; open[$1 FS $2] = $4; next }
		FILENAME == ARGV[2] { busy[$1 FS $2] = 1; next }
		NF >= 2 {
			k = $1 FS $2
			if (!(k in last)) order[++n] = k
			if (!(k in last) || $3 + 0 > last[k]) last[k] = $3 + 0
		}
		END {
			for (i = 1; i <= n; i++) {
				k = order[i]; l = last[k]
				if ((k in act) && act[k] + 0 > l) l = act[k] + 0
				b = ((k in busy) || open[k] + 0 > 0) ? 1 : 0
				print k, l, b
			}
		}' "$activity" <(printf '%s' "$others") <(printf '%s' "$servers")
}

# Is anything besides the server itself keeping <project>/<wt> busy?
_router_instance_busy() {
	local line
	line=$(_router_instances | awk -F'\t' -v p="$1" -v w="$2" '$1 == p && $2 == w')
	[ -n "$line" ] && [ "${line##*$'\t'}" = 1 ]
}

# Stop every server job of one instance. Exit 3 when pwt runs none (a
# foreground server in someone's terminal is not ours to stop).
router_stop_instance() {
	local project="$1" wt="$2" f id stopped=0
	load_module jobs
	for f in "${PWT_JOBS_DIR:-$PWT_DIR/jobs}"/*.job; do
		[ -f "$f" ] || continue
		[ "$(state_get "$f" "command")" = server ] || continue
		[ "$(state_get "$f" "project")" = "$project" ] || continue
		[ "$(state_get "$f" "worktree")" = "$wt" ] || continue
		[ "$(state_get "$f" "status")" = running ] || continue
		id=$(state_get "$f" "id")
		_is_job_alive "$id" || continue
		_stop_job "$id"
		stopped=$((stopped + 1))
	done
	[ "$stopped" -gt 0 ] || return "$EXIT_NOT_FOUND"
	return 0
}

# Make room for <project>/<wt> under router.max_servers by stopping the
# least recently used idle instance; refuse (exit 4) when all are busy.
router_enforce_cap() {
	local project="$1" wt="$2" cap others count victim last_victim=""
	cap=$(_router_get max_servers)
	[[ "$cap" =~ ^[0-9]+$ ]] && [ "$cap" -gt 0 ] || return 0
	while :; do
		others=$(_router_instances | awk -F'\t' -v p="$project" -v w="$wt" '!($1 == p && $2 == w)')
		count=$(printf '%s' "$others" | grep -c . || true)
		[ "$count" -lt "$cap" ] && return 0
		victim=$(printf '%s\n' "$others" | awk -F'\t' '$4 == "0"' | sort -t$'\t' -k3,3n | head -1)
		if [ -z "$victim" ] || [ "$victim" = "$last_victim" ]; then
			pwt_error "Error: server cap reached ($count of $cap running, none idle)"
			echo "  Running: $(printf '%s\n' "$others" | awk -F'\t' '{ printf "%s%s/%s", s, $1, $2; s = ", " }')" >&2
			echo "  Stop one with: pwt <project> servers stop <worktree>" >&2
			echo "  Or raise the cap: pwt router config max_servers <n>" >&2
			return "$EXIT_CONFLICT"
		fi
		last_victim="$victim"
		local vp vw
		vp=$(printf '%s' "$victim" | cut -f1)
		vw=$(printf '%s' "$victim" | cut -f2)
		echo "Server cap ($cap) reached: stopping the least recently used idle server, $vp/$vw" >&2
		router_stop_instance "$vp" "$vw" >/dev/null || true
		events_append "$vp" "$vw" "server_evicted" "cap=$cap for=$project/$wt"
	done
}

# Last router activity for one instance: "<epoch> <in-flight>" or empty
router_activity() {
	local f
	f=$(_router_activity_file)
	[ -f "$f" ] || return 0
	awk -F'\t' -v p="$1" -v w="$2" '$1 == p && $2 == w { print $3, $4; exit }' "$f"
}

# ------------------------------------------------------------
# Daemon
# ------------------------------------------------------------

_router_node_env() {
	PWT_ROUTER_PORT="$(_router_get port)" \
		PWT_ROUTER_LISTEN="$(_router_get listen)" \
		PWT_BIN="$(_pwt_realpath "$0")" \
		PWT_DIR="$PWT_DIR" \
		PWT_NO_UPDATE_CHECK=1 \
		"$@"
}

_router_start() {
	local port pid_file log_file pid
	port=$(_router_get port)
	_router_is_running && return 0
	if ! command -v node >/dev/null 2>&1; then
		pwt_error "Error: node is required for pwt router"
		return "$EXIT_DEPENDENCY"
	fi
	if _boot_port_open "$port"; then
		pwt_error "Error: Router port $port is already in use by another process"
		echo "  Pick another: pwt router up --port <port>" >&2
		return "$EXIT_CONFLICT"
	fi
	mkdir -p "$(_router_dir)"
	pid_file=$(_router_pid_file)
	log_file=$(_router_log_file)
	pid=$(_router_node_env _pwt_daemonize "$log_file" append node "$PWT_LIB/router.js")
	if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
		pwt_error "Error: Router failed to spawn"
		return "$EXIT_ERROR"
	fi
	echo "$pid" >|"$pid_file"
	rm -f "$(_router_dir)/ready"
	local waited=0
	# Ready = the router wrote its pid to `ready` after opening every
	# public port (a listening control port alone is not enough)
	while [ "$(cat "$(_router_dir)/ready" 2>/dev/null)" != "$pid" ]; do
		if ! kill -0 "$pid" 2>/dev/null; then
			rm -f "$pid_file"
			pwt_error "Error: Router failed to start"
			tail -20 "$log_file" >&2 2>/dev/null || true
			return "$EXIT_ERROR"
		fi
		if [ "$waited" -ge 600 ]; then
			kill -TERM "$pid" 2>/dev/null || true
			rm -f "$pid_file"
			pwt_error "Error: Router did not become ready on port $port within 30s"
			tail -20 "$log_file" >&2 2>/dev/null || true
			return "$EXIT_ERROR"
		fi
		sleep 0.05
		waited=$((waited + 1))
	done
}

_router_stop() {
	local pid_file pid tries=20
	pid_file=$(_router_pid_file)
	if ! _router_is_running; then
		rm -f "$pid_file"
		echo "Router is not running"
		return 0
	fi
	pid=$(cat "$pid_file")
	kill -TERM "$pid" 2>/dev/null || true
	while [ "$tries" -gt 0 ] && kill -0 "$pid" 2>/dev/null; do
		sleep 0.05
		tries=$((tries - 1))
	done
	kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
	rm -f "$pid_file"
	echo "Router stopped"
}

# ------------------------------------------------------------
# Commands
# ------------------------------------------------------------

_router_set_option() {
	local key="$1" value="$2"
	if ! _router_key_default "$key" >/dev/null; then
		pwt_error "Error: Unknown router setting: $key"
		echo "  Settings: $(printf '%s\n' "$_ROUTER_KEYS" | cut -f1 | tr '\n' ' ')" >&2
		return "$EXIT_USAGE"
	fi
	case "$key" in
		port | port_offset | hold_seconds | boot_timeout | max_servers)
			if ! [[ "$value" =~ ^[0-9]+$ ]]; then
				pwt_error "Error: $key takes a whole number (got '$value')"
				return "$EXIT_USAGE"
			fi
			;;
		idle_minutes)
			if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
				pwt_error "Error: idle_minutes takes a number of minutes (got '$value')"
				return "$EXIT_USAGE"
			fi
			;;
		domain)
			if [ -n "$value" ] && ! [[ "$value" =~ ^[A-Za-z0-9.-]+$ ]]; then
				pwt_error "Error: domain must be a hostname without scheme or port"
				return "$EXIT_USAGE"
			fi
			;;
		template | alias_template | main_template | main_alias_template)
			if ! [[ "$value" =~ ^[A-Za-z0-9.{}-]+$ ]]; then
				pwt_error "Error: $key may contain letters, digits, '.', '-' and {project} {worktree} {alias}"
				return "$EXIT_USAGE"
			fi
			;;
		host_routing | expose_logs)
			if [ "$value" != true ] && [ "$value" != false ]; then
				pwt_error "Error: $key is true or false"
				return "$EXIT_USAGE"
			fi
			;;
		scheme)
			if [ "$value" != http ] && [ "$value" != https ]; then
				pwt_error "Error: scheme is http or https"
				return "$EXIT_USAGE"
			fi
			;;
	esac
	state_set "$PWT_DIR/config" "router.$key" "$value"
}

_router_routes() {
	local format="${1:-text}" routes hosts
	routes=$(_router_rows | _router_render)
	hosts=$(_router_get host_routing)
	case "$format" in
		porcelain)
			[ -n "$routes" ] && printf '%s\n' "$routes"
			;;
		json)
			local host p w port alias var pub rows=""
			while IFS=$'\037' read -r host p w port alias var pub; do
				[ -n "$host" ] || continue
				[ -z "$alias" ] || [ "$hosts" = true ] || continue
				rows="${rows:+$rows,}$(printf '{"project":%s,"worktree":%s,"port":%s,"public_port":%s,"public_url":%s,"host":%s,"alias":%s}' \
					"$(json_str "$p")" "$(json_str "$w")" "$(json_num_or_null "$port")" \
					"$(json_num_or_null "$pub")" "$(json_str_or_null "${pub:+http://localhost:$pub}")" \
					"$(json_str_or_null "$([ "$hosts" = true ] && echo "$host")")" "$(json_str_or_null "$alias")")"
			done <<<"$(printf '%s' "$routes" | tr '\t' '\037')"
			printf '[%s]\n' "$rows"
			;;
		*)
			if [ -z "$routes" ]; then
				echo "(no routes: no project has a worktree with a port yet)"
				return 0
			fi
			if [ "$hosts" = true ]; then
				printf '%-8s %-20s %-28s %-6s %s\n' "PUBLIC" "PROJECT" "WORKTREE" "PORT" "HOST"
			else
				printf '%-8s %-20s %-28s %s\n' "PUBLIC" "PROJECT" "WORKTREE" "PORT"
			fi
			printf '%s\n' "$routes" | tr '\t' '\037' | while IFS=$'\037' read -r host p w port alias var pub; do
				if [ "$hosts" = true ]; then
					printf '%-8s %-20s %-28s %-6s %s\n' "${pub:--}" "$p" "$w" "$port" "$host"
				elif [ -z "$alias" ]; then
					printf '%-8s %-20s %-28s %s\n' "${pub:--}" "$p" "$w" "$port"
				fi
			done
			;;
	esac
}

_router_status() {
	local json=false running=false pid="" port routes_count
	[ "${1:-}" = "--json" ] && json=true
	port=$(_router_get port)
	if _router_is_running; then
		running=true
		pid=$(cat "$(_router_pid_file)")
	fi
	routes_count=$(_router_rows | grep -c . || true)
	if [ "$json" = true ]; then
		printf '{"running":%s,"pid":%s,"port":%s,"listen":%s,"port_offset":%s,"host_routing":%s,"domain":%s,"template":%s,"idle_minutes":%s,"max_servers":%s,"boot_timeout":%s,"hold_seconds":%s,"instances":%s,"log":%s}\n' \
			"$running" "$(json_num_or_null "$pid")" "$(json_num_or_null "$port")" \
			"$(json_str "$(_router_get listen)")" "$(json_num_or_null "$(_router_get port_offset)")" \
			"$([ "$(_router_get host_routing)" = true ] && echo true || echo false)" \
			"$(json_str "$(_router_get domain)")" "$(json_str "$(_router_get template)")" \
			"$(json_str "$(_router_get idle_minutes)")" "$(json_num_or_null "$(_router_get max_servers)")" \
			"$(json_num_or_null "$(_router_get boot_timeout)")" "$(json_num_or_null "$(_router_get hold_seconds)")" \
			"$routes_count" "$(json_str "$(_router_log_file)")"
		return 0
	fi
	echo "Router: $([ "$running" = true ] && echo "running (pid $pid)" || echo "stopped")"
	echo "  Listen:       $(_router_get listen), status page on port $port"
	echo "  Public ports: pwt port + $(_router_get port_offset) (pwt router routes)"
	if [ "$(_router_get host_routing)" = true ]; then
		echo "  Hostnames:    $(_router_get template).$(_router_get domain) on port $port"
	fi
	echo "  Idle stop:    $(_router_get idle_minutes) min (0 = never)"
	echo "  Server cap:   $(_router_get max_servers) (0 = no cap)"
	echo "  Instances:    $routes_count"
}

_router_help() {
	cat <<'HELP'
Usage: pwt router <command> [args]

A stable public port for every worktree of every project on this machine.
The router owns the port while the server sleeps: the first request starts
the server (pwt server --bg) and is held until it listens, a browser sees
the boot steps live, and servers nobody used for idle_minutes are stopped.
Public port = the worktree's pwt port + port_offset (5012 -> 15012); the
server keeps binding PWT_PORT and the router forwards to it.

Commands:
  up [--port N] [--listen ADDRS]   Start the router (daemon)
  up --foreground                  Run in the foreground (systemd, containers)
  down                             Stop the router
  restart                          Restart the router
  status [--json]                  Show router state and policy
  routes [--json|--porcelain]      List every public port and where it goes
  url [worktree|@]                 Print a worktree's URL through the router
  config [key [value]]             Show or change settings (--unset to reset)
  logs [-f]                        Show the router log

Policy (pwt router config <key> <value>):
  idle_minutes 30     stop a server after 30 min without router traffic
  max_servers 2       cap running servers; the least recently used idle
                      one is stopped to make room (the main app @ is exempt)
  boot_timeout 120    report a boot failed after 120 s
  hold_seconds 30     how long an API/XHR request waits for a waking server

Host routing (off by default): pwt router config host_routing true routes
<worktree>.<project>.localhost on the router port; a Pwtfile hosts()
declares extra names ("api", or "*" for every label in front).
HELP
}

cmd_router() {
	local subcmd="${1:-status}"
	shift || true

	case "$subcmd" in
		-h | --help | help)
			_router_help
			;;
		up | start)
			local foreground=false
			while [ $# -gt 0 ]; do
				case "$1" in
					--port | -p)
						_router_set_option port "${2:-}" || return $?
						shift 2
						;;
					--listen)
						_router_set_option listen "${2:-}" || return $?
						shift 2
						;;
					--foreground)
						foreground=true
						shift
						;;
					*)
						pwt_error "Unknown option: $1"
						return "$EXIT_USAGE"
						;;
				esac
			done
			if [ "$foreground" = true ]; then
				command -v node >/dev/null 2>&1 || {
					pwt_error "Error: node is required for pwt router"
					return "$EXIT_DEPENDENCY"
				}
				_router_node_env exec node "$PWT_LIB/router.js"
			fi
			_router_start || return $?
			echo "Router running (status page: http://localhost:$(_router_get port))"
			echo "  Worktrees: pwt router routes"
			;;
		down | stop)
			_router_stop
			;;
		restart)
			_router_stop >/dev/null
			_router_start || return $?
			echo "Router running on port $(_router_get port)"
			;;
		status)
			_router_status "$@"
			;;
		routes)
			case "${1:-}" in
				--json) _router_routes json ;;
				--porcelain) _router_routes porcelain ;;
				"") _router_routes text ;;
				*)
					pwt_error "Unknown option: $1"
					return "$EXIT_USAGE"
					;;
			esac
			;;
		url)
			require_project
			local target="${1:-}" name
			if [ -z "$target" ]; then
				name=$(get_current_from_symlink 2>/dev/null || true)
				[[ "$PWD" == "$WORKTREES_DIR"/* ]] && name=$(basename "${PWD#"$WORKTREES_DIR"/}")
				name="${name%%/*}"
			elif [ "$target" = "@" ]; then
				name="@"
			else
				local path
				path=$(resolve_worktree_path "$target" 2>/dev/null || true)
				[ -n "$path" ] && [ -d "$path" ] && name=$(basename "$path")
			fi
			if [ -z "${name:-}" ]; then
				pwt_error "Error: Worktree not found: ${target:-(none current)}"
				return "$EXIT_NOT_FOUND"
			fi
			local wt_port
			if [ "$name" = "@" ]; then
				wt_port="${BASE_PORT:-5000}"
			else
				wt_port=$(get_metadata "$name" "port")
			fi
			router_export_env "$CURRENT_PROJECT" "$name" "$wt_port"
			if [ "$(_router_get host_routing)" = true ] && [ -n "$PWT_URL" ]; then
				echo "$PWT_URL"
				return 0
			fi
			if [ -z "$PWT_PUBLIC_URL" ]; then
				pwt_error "Error: No public port for $name (pwt port ${wt_port:-unknown})"
				return "$EXIT_NOT_FOUND"
			fi
			echo "$PWT_PUBLIC_URL"
			;;
		config)
			local key="${1:-}" value
			if [ -z "$key" ]; then
				printf '%s\n' "$_ROUTER_KEYS" | while IFS=$'\t' read -r key _ _; do
					printf '%s=%s\n' "$key" "$(_router_get "$key")"
				done
				return 0
			fi
			if ! _router_key_default "$key" >/dev/null; then
				_router_set_option "$key" "" # prints the error and the list
				return $?
			fi
			if [ $# -lt 2 ]; then
				_router_get "$key"
				return 0
			fi
			value="$2"
			if [ "$value" = "--unset" ]; then
				state_del "$PWT_DIR/config" "router.$key"
				echo "router.$key reset to default: $(_router_get "$key")"
				return 0
			fi
			_router_set_option "$key" "$value" || return $?
			echo "router.$key=$value"
			case "$key" in
				port | listen)
					_router_is_running && echo "  Restart to apply: pwt router restart"
					;;
			esac
			return 0
			;;
		logs | log)
			local log_file
			log_file=$(_router_log_file)
			[ -f "$log_file" ] || {
				echo "No router log found"
				return 0
			}
			if [ "${1:-}" = "-f" ] || [ "${1:-}" = "--follow" ]; then
				tail -f "$log_file"
			else
				tail -50 "$log_file"
			fi
			;;
		*)
			pwt_error "Unknown router command: $subcmd"
			echo "Run 'pwt router help' for usage" >&2
			return "$EXIT_USAGE"
			;;
	esac
}
