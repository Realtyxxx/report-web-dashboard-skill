#!/usr/bin/env bash
# ==============================================================================
# Report Web Dashboard Server Manager
# Usage: ./server.sh [start|run|stop|status|restart|list] [port]
#
# Multi-project isolation: the log file embeds the project name and port
# (/tmp/report_web_dashboard_server_<project>_<port>.log) so `list` can
# identify which project owns each running dashboard on this machine.
#
# Auto free-port fallback: `start`/`run` only. If the requested port is
# occupied by THIS project's own server (log file present), that's reported
# as already-running and nothing new is spawned. If it's occupied by
# anything else, the script probes forward (port+1, port+2, ...) up to
# MAX_PORT and launches there instead. `status`/`stop`/`restart` never
# auto-switch — they always act on the exact port you named.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${WORKSPACE_DIR:-$(pwd)}"
DEFAULT_PORT=8800
MAX_PORT=8899

ACTION="${1:-status}"
REQUESTED_PORT="${2:-$DEFAULT_PORT}"

# Derive project name from workspace directory for isolation
PROJECT_NAME=$(basename "$WORKSPACE_DIR" | sed 's/[^a-zA-Z0-9_-]/_/g')

log_file_for_port() {
    echo "/tmp/report_web_dashboard_server_${PROJECT_NAME}_${1}.log"
}

get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1"
}

is_port_listening() {
    local p="$1"
    python3 -c "import socket; s=socket.socket(); res=s.connect_ex(('127.0.0.1', $p)); s.close(); exit(0 if res==0 else 1)" 2>/dev/null
}

# Probe forward from $1 for the first free port, up to MAX_PORT. Prints the
# port on success; returns 1 (prints nothing) if the whole range is full.
find_free_port() {
    local port="$1"
    while [ "$port" -le "$MAX_PORT" ]; do
        if ! is_port_listening "$port"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    return 1
}

build_index_if_missing() {
    if [ ! -f "$WORKSPACE_DIR/index.html" ] && [ -f "$WORKSPACE_DIR/generate_web_dashboard.py" ]; then
        echo "[BUILD] Generating index.html using generate_web_dashboard.py..."
        python3 "$WORKSPACE_DIR/generate_web_dashboard.py"
    fi
}

# Resolves which port to actually use for a launch action (start/run).
# Echoes the resolved port. Echoes nothing and returns 1 if the requested
# port is already running THIS project's own server (caller should treat
# that as "already running", not an error).
resolve_launch_port() {
    local requested="$1"

    if ! is_port_listening "$requested"; then
        echo "$requested"
        return 0
    fi

    if [ -f "$(log_file_for_port "$requested")" ]; then
        # Occupied by our own project's server — caller reports "already running".
        return 1
    fi

    echo "[INFO] Port $requested is occupied by another service. Searching for a free port..." >&2
    local free_port
    if free_port=$(find_free_port "$((requested + 1))"); then
        echo "[INFO] Using free port $free_port instead." >&2
        echo "$free_port"
        return 0
    else
        echo "[ERROR] No free port available in range $((requested + 1))-$MAX_PORT." >&2
        return 2
    fi
}

start_server() {
    local port
    if ! port=$(resolve_launch_port "$REQUESTED_PORT"); then
        local status=$?
        if [ "$status" -eq 2 ]; then
            exit 1
        fi
        echo "[INFO] A server is ALREADY running on port $REQUESTED_PORT (this project)."
        echo "       URL: http://$(get_ip):$REQUESTED_PORT/"
        return 0
    fi

    local log_file
    log_file="$(log_file_for_port "$port")"

    build_index_if_missing

    echo "[START] Launching HTTP server on port $port (bind 0.0.0.0)..."
    cd "$WORKSPACE_DIR"
    nohup python3 -m http.server "$port" --bind 0.0.0.0 > "$log_file" 2>&1 & disown
    local new_pid=$!

    sleep 1

    if is_port_listening "$port"; then
        local ip
        ip="$(get_ip)"
        echo "========================================================================"
        echo " 🚀 Report Web Dashboard Server Started Successfully!"
        echo " Project: $PROJECT_NAME"
        echo " PID  : $new_pid"
        echo " Port : $port"
        echo " URL  : http://$ip:$port/"
        echo " Local: http://localhost:$port/"
        echo " Path : file://$WORKSPACE_DIR/index.html"
        echo " Log  : $log_file"
        echo "========================================================================"
    else
        echo "[ERROR] Failed to start HTTP server on port $port. Log tail:"
        tail -n 10 "$log_file" 2>/dev/null || true
        exit 1
    fi
}

stop_server() {
    local port="$REQUESTED_PORT"
    echo "[STOP] Stopping Report Web Dashboard server on port $port..."
    # Anchor the port with a word boundary so port 880 never matches 8800.
    pkill -f "http\.server $port( |\$)" 2>/dev/null || true
    sleep 1
    if ! is_port_listening "$port"; then
        rm -f "$(log_file_for_port "$port")"
        echo "[OK] Server on port $port stopped successfully."
    else
        echo "[WARNING] Could not verify server shutdown on port $port."
    fi
}

status_server() {
    local port="$REQUESTED_PORT"
    if is_port_listening "$port"; then
        local ip
        ip="$(get_ip)"
        echo "========================================================================"
        echo " 🟢 Report Web Dashboard Server is RUNNING on port $port"
        echo " URL  : http://$ip:$port/"
        echo " Local: http://localhost:$port/"
        echo " Path : file://$WORKSPACE_DIR/index.html"
        echo "========================================================================"
        return 0
    else
        echo "🔴 Report Web Dashboard Server is STOPPED on port $port."
        return 1
    fi
}

list_all_dashboards() {
    echo "========================================================================"
    echo " 📊 Report Web Dashboard Discovery (ports 8800-8899, whole machine)"
    echo "========================================================================"

    local found=0
    local ip
    ip="$(get_ip)"

    for port in {8800..8899}; do
        if is_port_listening "$port" 2>/dev/null; then
            local pid=""
            pid=$(lsof -i ":$port" 2>/dev/null | grep LISTEN | awk '{print $2}' | head -1) || true

            # Identify the owning project from the log file naming convention
            local project_name="unknown"
            for log_file in /tmp/report_web_dashboard_server_*_"$port".log; do
                if [ -f "$log_file" ]; then
                    project_name=$(basename "$log_file" | sed 's/report_web_dashboard_server_//; s/_[0-9]*\.log//')
                    break
                fi
            done

            echo " 🟢 [$port] $project_name"
            echo "     URL  : http://$ip:$port"
            echo "     Local: http://localhost:$port"
            [ -n "$pid" ] && echo "     PID  : $pid"
            echo ""

            found=$((found + 1))
        fi
    done

    if [ $found -eq 0 ]; then
        echo " ℹ️  No Report Web Dashboard services found running on ports 8800-8899"
        echo ""
        return 1
    else
        echo "========================================================================"
        echo " Found: $found service(s) running"
        echo "========================================================================"
        return 0
    fi
}

case "$ACTION" in
    start)
        start_server
        ;;
    run)
        port=""
        if ! port=$(resolve_launch_port "$REQUESTED_PORT"); then
            status=$?
            if [ "$status" -eq 2 ]; then
                exit 1
            fi
            echo "[INFO] A server is ALREADY running on port $REQUESTED_PORT (this project, background)."
            echo "       Stop it first with './server.sh stop $REQUESTED_PORT', or pick another port."
            exit 1
        fi
        build_index_if_missing
        echo "[RUN] Starting HTTP server on port $port in foreground (Ctrl+C to stop)..."
        cd "$WORKSPACE_DIR"
        exec python3 -m http.server "$port" --bind 0.0.0.0
        ;;
    stop)
        stop_server
        ;;
    status)
        status_server || true
        ;;
    restart)
        stop_server
        sleep 1
        start_server
        ;;
    list)
        list_all_dashboards
        ;;
    *)
        echo "Usage: $0 {start|run|stop|status|restart|list} [port]"
        exit 1
        ;;
esac
