#!/usr/bin/env bash
# Auto-started by .devcontainer/dev/devcontainer.json `postStartCommand` on every devcontainer
# start. Brings up a Jupyter server INSIDE this container plus a host-published socat bridge,
# so Cursor/VS Code running on the HOST can attach a remote kernel to `# %%` .py scripts
# (no .ipynb, no host venv, no IDE-in-container).
#
# MULTIPLE devcontainers on one host are supported: Jupyter always binds :8888 INSIDE its own
# container (separate network namespaces never collide), and the HOST-published port is
# auto-assigned to the first free port from 8888 up, then persisted per-repo so it — and your
# saved IDE connection — stay stable across rebuilds. Each devcontainer has its own container
# and venv, hence its own kernels.
#
# jupyterlab + ipykernel come from an ephemeral `uv run --with` overlay (not added to any
# project's pyproject.toml / uv.lock). Idempotent and non-fatal (never blocks container start).
# Opt out with JUPYTER_BRIDGE_DISABLE=1; force a host port with JUPYTER_BRIDGE_PORT.
set -uo pipefail

if [ "${JUPYTER_BRIDGE_DISABLE:-0}" = "1" ]; then
    echo "[jupyter-bridge] disabled via JUPYTER_BRIDGE_DISABLE=1"
    exit 0
fi

INTERNAL_PORT=8888 # jupyter's port INSIDE this container (does not collide across containers)
REPO=/usr/src
KSRC="$REPO/.devcontainer/jupyter/kernels"
KDST="$HOME/.local/share/jupyter/kernels"
RUNTIME="$REPO/.jupyter-runtime"
TOKEN_FILE="$RUNTIME/token"
PORT_FILE="$RUNTIME/host-port"
PROXY_FILE="$RUNTIME/proxy"
LOG="$RUNTIME/server.log"
UV="$HOME/.local/bin/uv"
command -v uv >/dev/null 2>&1 && UV="$(command -v uv)"

mkdir -p "$RUNTIME"

# 1) (re)install the named kernelspecs.
for p in library backend; do
    if [ -f "$KSRC/ti-core-$p.json" ]; then
        mkdir -p "$KDST/ti-core-$p"
        cp "$KSRC/ti-core-$p.json" "$KDST/ti-core-$p/kernel.json"
    fi
done

# 2) persistent token (random, per-repo, loopback-only) — reused across restarts/rebuilds so
#    saved IDE connections keep working.
if [ -s "$TOKEN_FILE" ]; then
    TOKEN="$(cat "$TOKEN_FILE")"
else
    TOKEN="$(openssl rand -hex 24 2>/dev/null || head -c24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf '%s' "$TOKEN" >"$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE" 2>/dev/null || true
fi

# 3) (re)launch the Jupyter server in the background on the fixed INTERNAL_PORT.
pkill -f "[j]upyter-lab.*ServerApp.port=$INTERNAL_PORT" 2>/dev/null || true
(cd "$REPO/library" && nohup setsid "$UV" run --with jupyterlab --with ipykernel \
    jupyter lab --no-browser \
    --ServerApp.ip=0.0.0.0 --ServerApp.port="$INTERNAL_PORT" --ServerApp.token="$TOKEN" \
    --ServerApp.allow_origin='*' --ServerApp.allow_remote_access=True \
    --ServerApp.root_dir="$REPO" \
    >"$LOG" 2>&1 </dev/null &)

# 4) (re)create the host-published socat bridge on a FREE host port. The host cannot route to
#    the container network directly, so socat publishes 127.0.0.1:<hostport> -> this container's
#    :INTERNAL_PORT. Uses docker-outside-of-docker; the obt container is never modified.
if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    SELF="$(hostname)"
    SELF_NAME="$(docker inspect "$SELF" --format '{{.Name}}' 2>/dev/null | sed 's#^/##')"
    [ -z "$SELF_NAME" ] && SELF_NAME="$SELF"
    NET="$(docker inspect "$SELF" --format '{{range $n,$c := .NetworkSettings.Networks}}{{$n}}{{"\n"}}{{end}}' 2>/dev/null | grep -v traefik | head -1)"
    [ -z "$NET" ] && NET="$(docker inspect "$SELF" --format '{{range $n,$c := .NetworkSettings.Networks}}{{$n}}{{"\n"}}{{end}}' 2>/dev/null | head -1)"
    PREFIX="${SELF_NAME%-obt-*}"
    [ "$PREFIX" = "$SELF_NAME" ] && PREFIX=ti-core
    PROXY="${PREFIX}-jupyter-proxy" # one bridge per devcontainer
    printf '%s' "$PROXY" >"$PROXY_FILE"

    # candidate host port: explicit override, else the persisted one, else 8888.
    if [ -n "${JUPYTER_BRIDGE_PORT-}" ]; then
        CAND="$JUPYTER_BRIDGE_PORT"
    elif [ -s "$PORT_FILE" ]; then
        CAND="$(cat "$PORT_FILE")"
    else
        CAND="$INTERNAL_PORT"
    fi

    HOST_PORT=""
    if [ -n "$NET" ]; then
        docker rm -f "$PROXY" >/dev/null 2>&1 || true # drop this devcontainer's previous bridge
        for off in $(seq 0 40); do
            p=$((CAND + off))
            if docker run -d --name "$PROXY" --network "$NET" \
                -p "127.0.0.1:$p:$INTERNAL_PORT" alpine/socat \
                TCP-LISTEN:$INTERNAL_PORT,fork,reuseaddr "TCP:$SELF_NAME:$INTERNAL_PORT" >/dev/null 2>&1; then
                HOST_PORT=$p
                break
            fi
            docker rm -f "$PROXY" >/dev/null 2>&1 || true # clear failed/half-created container
        done
    fi

    if [ -n "$HOST_PORT" ]; then
        printf '%s' "$HOST_PORT" >"$PORT_FILE"
        echo "[jupyter-bridge] host bridge $PROXY: 127.0.0.1:$HOST_PORT -> $SELF_NAME:$INTERNAL_PORT on $NET"
    else
        echo "[jupyter-bridge] WARN: could not allocate a free host port for the bridge"
    fi
else
    echo "[jupyter-bridge] WARN: docker not reachable; host bridge not created"
fi

echo "[jupyter-bridge] token: $TOKEN_FILE, host-port: $PORT_FILE, log: $LOG"
echo "[jupyter-bridge] connect URL: run  bash .devcontainer/jupyter/connect.sh url  on the host"
exit 0
