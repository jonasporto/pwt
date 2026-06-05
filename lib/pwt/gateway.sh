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
    echo "$PROJECTS_DIR/$CURRENT_PROJECT/config.json"
}

_gateway_state_file() {
    echo "$(_gateway_project_dir)/gateway.json"
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

    mkdir -p "$(dirname "$config_file")"
    [ -f "$config_file" ] || echo "{}" > "$config_file"
    local tmp_file
    tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    jq --arg port "$port" '.gateway_port = $port' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
}

_gateway_set_host() {
    local host="$1"
    local config_file=$(_gateway_config_file)

    _gateway_validate_host "$host" || return $?

    mkdir -p "$(dirname "$config_file")"
    [ -f "$config_file" ] || echo "{}" > "$config_file"
    local tmp_file
    tmp_file="$(mktemp "${config_file}.tmp.XXXXXX")"
    jq --arg host "$host" '.gateway_host = $host' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
}

_gateway_is_running() {
    local pid_file=$(_gateway_pid_file)
    [ -f "$pid_file" ] || return 1
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

_gateway_target_name() {
    local state_file=$(_gateway_state_file)
    [ -f "$state_file" ] || return 0
    jq -r '.target // empty' "$state_file" 2>/dev/null
}

_gateway_target_port() {
    local state_file=$(_gateway_state_file)
    [ -f "$state_file" ] || return 0
    jq -r '.target_port // empty' "$state_file" 2>/dev/null
}

_gateway_write_proxy_script() {
    local script=$(_gateway_proxy_script)
    mkdir -p "$(dirname "$script")"
    cat > "$script" <<'NODE'
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
    const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
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
    [ -f "$state_file" ] || echo '{}' > "$state_file"
    _gateway_write_proxy_script

    local pid
    pid=$(
        PWT_GATEWAY_HOST="127.0.0.1" \
        PWT_GATEWAY_PORT="$port" \
        PWT_GATEWAY_STATE="$state_file" \
        PWT_GATEWAY_PROJECT="$CURRENT_PROJECT" \
            node - "$script" "$log_file" <<'NODE'
const { spawn } = require("child_process");
const fs = require("fs");

const script = process.argv[2];
const logFile = process.argv[3];
const out = fs.openSync(logFile, "a");
const child = spawn(process.execPath, [script], {
  detached: true,
  stdio: ["ignore", out, out],
  env: process.env
});

child.unref();
console.log(child.pid);
NODE
    )
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        pwt_error "Error: Gateway failed to spawn"
        return $EXIT_ERROR
    fi
    echo "$pid" > "$pid_file"

    sleep 0.5
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$pid_file"
        pwt_error "Error: Gateway failed to start"
        tail -20 "$log_file" 2>/dev/null || true
        return $EXIT_ERROR
    fi
    if ! _gateway_wait_for_port "$port"; then
        kill -TERM "$pid" 2>/dev/null || true
        rm -f "$pid_file"
        pwt_error "Error: Gateway did not start listening on port $port"
        tail -20 "$log_file" 2>/dev/null || true
        return $EXIT_ERROR
    fi
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
    sleep 0.5
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
    local attempts=$((seconds * 5))
    [ "$attempts" -lt 1 ] && attempts=1

    while [ "$attempts" -gt 0 ]; do
        if _gateway_port_listening "$port"; then
            return 0
        fi
        sleep 0.2
        attempts=$((attempts - 1))
    done
    return 1
}

_gateway_port_listening() {
    local port="$1"
    [ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]] || return 1
    if has_lsof; then
        [ -n "$(get_pids_on_port "$port")" ]
        return $?
    fi
    (echo > "/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1
}

_gateway_save_target() {
    local name="$1"
    local path="$2"
    local port="$3"
    local branch="$4"
    local state_file=$(_gateway_state_file)

    mkdir -p "$(dirname "$state_file")"
    jq -n \
        --arg project "$CURRENT_PROJECT" \
        --arg target "$name" \
        --arg path "$path" \
        --arg branch "$branch" \
        --argjson target_port "$port" \
        --arg updated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{
            project: $project,
            target: $target,
            target_path: $path,
            target_port: $target_port,
            branch: $branch,
            updated_at: $updated_at
        }' > "$state_file"
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
    IFS=$'\t' read -r name path port branch <<< "$resolved"

    if ! _gateway_port_listening "$port"; then
        if has_pwtfile_command "server"; then
            echo "Starting server for $name on port $port..."
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

    _gateway_save_target "$name" "$path" "$port" "$branch"
    _gateway_start "$gateway_port"

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
        jq -n -c \
            --arg project "$CURRENT_PROJECT" \
            --arg port "$port" \
            --arg host "$host" \
            --arg target "$target" \
            --arg target_port "$target_port" \
            --arg pid "$pid" \
            --argjson running "$running" \
            '{
                project: $project,
                configured: ($port != ""),
                port: (if $port != "" then ($port | tonumber) else null end),
                host: $host,
                url: (if $port != "" then "http://" + $host + ":" + $port else null end),
                running: $running,
                pid: (if $pid != "" then ($pid | tonumber) else null end),
                target: (if $target != "" then $target else null end),
                target_port: (if $target_port != "" then ($target_port | tonumber) else null end)
            }'
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

_servers_job_status_for() {
    local name="$1"
    local status=""
    load_module jobs

    local json_file
    for json_file in "$PWT_JOBS_DIR"/*.json; do
        [ -f "$json_file" ] || continue
        local j_wt j_cmd j_id j_status
        j_wt=$(jq -r '.worktree // empty' "$json_file" 2>/dev/null)
        j_cmd=$(jq -r '.command // empty' "$json_file" 2>/dev/null)
        j_id=$(jq -r '.id // empty' "$json_file" 2>/dev/null)
        j_status=$(jq -r '.status // empty' "$json_file" 2>/dev/null)
        [ "$j_wt" = "$name" ] && [ "$j_cmd" = "server" ] || continue
        if [ "$j_status" = "running" ] && _is_job_alive "$j_id"; then
            status="job:$j_id"
            break
        fi
    done
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

    if [ -n "$port" ] && [[ "$port" =~ ^[0-9]+$ ]] && _gateway_port_listening "$port"; then
        listening="listening"
    fi
    job_status=$(_servers_job_status_for "$name")
    [ -z "$job_status" ] && job_status="-"

    printf "%-24s %-8s %-10s %-18s %s\n" "$name" "${port:-"-"}" "$listening" "$job_status" "$markers"
    [ -n "$branch" ] && printf "  branch: %s\n" "$branch"
    printf "  path:   %s\n" "$path"
}

cmd_servers() {
    local show_all=false
    local json=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --all|-a) show_all=true; shift ;;
            --json) json=true; shift ;;
            -h|--help|help)
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
        local rows="[]"
        local name path port branch listening job marker row
        while IFS=$'\t' read -r name path; do
            [ -n "$name" ] && [ -d "$path" ] || continue
            port=$(get_metadata "$name" "port")
            branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "")
            listening=false
            [ -n "$port" ] && _gateway_port_listening "$port" && listening=true
            job=$(_servers_job_status_for "$name")
            marker=""
            [ "$name" = "$gateway_target" ] && marker="${marker}gateway "
            [ "$name" = "$current" ] && marker="${marker}current "
            if [ "$show_all" = true ] || [ "$listening" = true ] || [ -n "$job" ] || [ -n "$marker" ]; then
                row=$(jq -n \
                    --arg name "$name" --arg path "$path" --arg port "$port" \
                    --arg branch "$branch" --arg job "$job" --arg marker "${marker% }" \
                    --argjson listening "$listening" \
                    '{
                        "name": $name,
                        "path": $path,
                        "port": (if $port != "" then ($port | tonumber) else null end),
                        "branch": $branch,
                        "listening": $listening,
                        "job": (if $job != "" then $job else null end),
                        "marker": $marker
                    }')
                rows=$(echo "$rows" | jq --argjson row "$row" '. + [$row]')
            fi
        done < <(list_known_worktree_entries)
        jq -n -c \
            --arg project "$CURRENT_PROJECT" \
            --arg gateway_port "$gateway_port" \
            --arg gateway_target "$gateway_target" \
            --arg current "$current" \
            --argjson gateway_running "$gateway_running" \
            --argjson has_server "$has_server" \
            --argjson servers "$rows" \
            '{
                "project": $project,
                "pwtfile_server": $has_server,
                "gateway": {
                    "configured": ($gateway_port != ""),
                    "port": (if $gateway_port != "" then ($gateway_port | tonumber) else null end),
                    "running": $gateway_running,
                    "target": (if $gateway_target != "" then $gateway_target else null end)
                },
                "current": (if $current != "" then $current else null end),
                "servers": $servers
            }'
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
        [ -n "$port" ] && _gateway_port_listening "$port" && listening=true
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
        -h|--help|help)
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
                    --port|-p) port="${2:-}"; shift 2 ;;
                    --host|-H) host="${2:-}"; shift 2 ;;
                    *) port="$1"; shift ;;
                esac
            done
            if ! [[ "$port" =~ ^[0-9]+$ ]]; then
                pwt_error "Error: gateway init requires --port <port>"
                return $EXIT_USAGE
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
        up|start)
            local port
            while [ $# -gt 0 ]; do
                case "$1" in
                    --port|-p)
                        _gateway_set_port "${2:-}" || return $?
                        shift 2
                        ;;
                    --host|-H)
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
        down|stop)
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
        logs|log)
            local log_file=$(_gateway_log_file)
            [ -f "$log_file" ] || { echo "No gateway log found"; return 0; }
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
