#!/usr/bin/env bash
# Host-side helper for the devcontainer Jupyter bridge (auto-started by the devcontainer
# postStartCommand). Run from the HOST, from anywhere in the repo. The host port is auto-
# assigned per devcontainer and recorded in /.jupyter-runtime/, so this always reports the
# correct URL even when multiple devcontainers run at once.
#
#   bash .devcontainer/jupyter/connect.sh url       # print the Cursor connect URL + token
#   bash .devcontainer/jupyter/connect.sh status    # server reachability + connect URL
#   bash .devcontainer/jupyter/connect.sh restart   # re-run autostart inside the container
#   bash .devcontainer/jupyter/connect.sh stop      # stop server + host bridge
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME="$REPO/.jupyter-runtime"
TOKEN_FILE="$RUNTIME/token"
PORT_FILE="$RUNTIME/host-port"
PROXY_FILE="$RUNTIME/proxy"

read_file() { [ -s "$1" ] && cat "$1" || echo ""; }

print_url() {
    local port token
    port="$(read_file "$PORT_FILE")"
    token="$(read_file "$TOKEN_FILE")"
    if [ -z "$port" ] || [ -z "$token" ]; then
        echo "Bridge not ready yet ($RUNTIME). Is the devcontainer up? Try: $0 restart" >&2
        return 1
    fi
    # bare URL on stdout (clean to copy/paste); usage hint to stderr.
    echo "http://localhost:$port/?token=$token"
}

case "${1:-url}" in
url)
    print_url && echo "  ^ in Cursor: 'Specify Jupyter Server for Connections' -> Existing -> paste; kernel 'TI Core (library)' or 'TI Core (backend)'" >&2
    ;;
status)
    port="$(read_file "$PORT_FILE")"
    if [ -z "$port" ]; then
        echo "no host-port recorded yet ($PORT_FILE) — is the devcontainer up?"
        exit 0
    fi
    code=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://localhost:$port/api/status" 2>/dev/null || echo 000)
    if [ "$code" = 200 ] || [ "$code" = 403 ]; then state=UP; else state="not reachable"; fi
    echo "host http://localhost:$port/api/status -> $code  ($state)"
    print_url || true
    ;;
restart)
    (cd "$REPO" && task obt:devcontainer-exec -- bash /usr/src/.devcontainer/jupyter/autostart.sh)
    ;;
stop)
    (cd "$REPO" && task obt:devcontainer-exec -- bash -lc "pkill -f '[j]upyter-lab.*ServerApp.port=8888' 2>/dev/null || true")
    proxy="$(read_file "$PROXY_FILE")"
    [ -n "$proxy" ] && docker rm -f "$proxy" >/dev/null 2>&1 || true
    echo "stopped (server + bridge)."
    ;;
*)
    echo "usage: $0 {url|status|restart|stop}"
    exit 1
    ;;
esac
