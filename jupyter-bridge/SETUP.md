# Jupyter Bridge — Setup & Replication Guide

This document explains, end to end, how the devcontainer Jupyter bridge is built so it can be
**recreated from scratch** in another repo (or rebuilt here if the files are lost). For day-to-day
*usage*, see [`README.md`](./README.md). This file is the *how it's wired and why* reference.

> **Source of truth & persistence:** these files are gitignored in ti-core. The canonical copy
> lives in `rboch-om1/dotfiles` under `jupyter-bridge/`; the dotfiles `setup` script (run by the
> devenv provisioner on every rebuild, or manually) copies them into
> `~/code/ti-core/.devcontainer/jupyter/`, and `clean_repos.sh` excludes that directory from its
> `git clean`. **Edit in dotfiles, then re-run `setup`** — direct edits in ti-core get overwritten.

---

## 1. What this achieves

Run plain `.py` scripts cell-by-cell (VS Code / Cursor "Interactive Window", `# %%` cells) against
the project's **real devcontainer environment**, while editing on the **host** IDE. The goals that
shape every design decision below:

- **No `.ipynb` files** — scripts stay as `.py` with `# %%` markers (diff-friendly, git-friendly).
- **No second/host virtualenv** — the kernel *is* the project's `uv` environment inside the container.
- **No IDE-in-container** — you keep editing on the host; only the kernel runs in the container.
- **`ipykernel`/`jupyterlab` are never project dependencies** — they are pulled ephemerally by
  `uv run --with`, so `pyproject.toml`/`uv.lock` are never touched.
- **The `obt` container is never modified** — the host↔container network gap is bridged by a
  *separate* `socat` sidecar container, started via docker-outside-of-docker.
- **Multiple devcontainers coexist** — each gets its own host port and token, persisted per-repo.

## 2. The core problem it solves

The host IDE cannot route directly to the devcontainer's internal Docker network. A kernel running
inside the container listens on `:8888` *inside* the container, which the host can't reach. Rather
than publishing a port on the `obt` container itself (which OBT owns and overwrites), we run a tiny
`alpine/socat` container on the same Docker network that forwards
`127.0.0.1:<hostport>` (published to the host loopback) → `obt-container:8888`.

```
Host IDE (Cursor/VS Code)
   │  http://localhost:<hostport>/?token=…
   ▼
127.0.0.1:<hostport>  ── published by ──►  socat sidecar container (alpine/socat)
                                                │  TCP:<obt-container>:8888
                                                ▼
                                       Jupyter Lab server (inside obt devcontainer, :8888)
                                                │  launches kernels via `uv run --with ipykernel`
                                                ▼
                                       TI Core (library) / TI Core (backend) kernels
```

## 3. File inventory

Everything lives in `.devcontainer/jupyter/` plus two small wiring points outside it.

| File | Role |
|------|------|
| `.devcontainer/jupyter/autostart.sh` | **Container-side.** Installs kernelspecs, starts Jupyter, creates the socat host bridge. Run on every container start. |
| `.devcontainer/jupyter/connect.sh` | **Host-side.** Reports the connect URL / status; restarts / stops the bridge. |
| `.devcontainer/jupyter/kernels/ti-core-library.json` | Kernelspec for the `library` project (`uv --project /usr/src/library`). |
| `.devcontainer/jupyter/kernels/ti-core-backend.json` | Kernelspec for the `backend` project (`uv --project /usr/src/backend`). |
| `.devcontainer/jupyter/README.md` | User-facing usage guide. |
| `.devcontainer/jupyter/SETUP.md` | This replication guide. |

**Wiring points (outside the folder):**

1. `.devcontainer/dev/devcontainer.json` → `postStartCommand` runs `autostart.sh` on every start:
   ```jsonc
   "postStartCommand": "bash .devcontainer/jupyter/autostart.sh || true",
   ```
   The `|| true` guarantees a bridge failure can never block container startup.

2. `Taskfile.yml` → four convenience tasks that wrap `connect.sh`:
   ```yaml
   jupyter-url:
     desc: "Print the Jupyter bridge URL to paste into Cursor"
     silent: true
     cmds: ["bash {{.TASKFILE_DIR}}/.devcontainer/jupyter/connect.sh url"]
   jupyter-status:
     desc: "Show Jupyter bridge reachability + connect URL"
     silent: true
     cmds: ["bash {{.TASKFILE_DIR}}/.devcontainer/jupyter/connect.sh status"]
   jupyter-restart:
     desc: "Restart the Jupyter bridge inside the devcontainer"
     cmds: ["bash {{.TASKFILE_DIR}}/.devcontainer/jupyter/connect.sh restart"]
   jupyter-stop:
     desc: "Stop the Jupyter bridge (server + host port-bridge)"
     cmds: ["bash {{.TASKFILE_DIR}}/.devcontainer/jupyter/connect.sh stop"]
   ```

3. `.gitignore` → the per-repo runtime state directory must be ignored:
   ```
   /.jupyter-runtime/
   ```

## 4. Runtime state — `/.jupyter-runtime/`

Created at the repo root inside the container (`/usr/src/.jupyter-runtime/`), gitignored, holds
per-repo state that is **reused across restarts/rebuilds** so saved IDE connections keep working:

| File | Contents |
|------|----------|
| `token` | Random hex token (24 bytes), generated once, `chmod 600`. Stable across rebuilds. |
| `host-port` | The host port chosen for this repo's bridge (first free port from 8888 up). |
| `proxy` | Name of this repo's socat sidecar container (e.g. `ti-core-jupyter-proxy`). |
| `server.log` | Jupyter server stdout/stderr. |

## 5. How `autostart.sh` works (container-side, step by step)

Runs as the `postStartCommand`. `set -uo pipefail`; every step is idempotent and non-fatal.

1. **Opt-out gate.** If `JUPYTER_BRIDGE_DISABLE=1`, print a message and exit 0.
2. **Install kernelspecs.** For `library` and `backend`, copy
   `kernels/ti-core-<p>.json` → `~/.local/share/jupyter/kernels/ti-core-<p>/kernel.json`.
3. **Persistent token.** If `/.jupyter-runtime/token` exists and is non-empty, reuse it; otherwise
   generate one (`openssl rand -hex 24`, fallback to `/dev/urandom`), write it, `chmod 600`.
4. **Launch Jupyter Lab** on the fixed internal port `8888`, in the background via `nohup setsid`:
   ```bash
   (cd /usr/src/library && nohup setsid uv run --with jupyterlab --with ipykernel \
       jupyter lab --no-browser \
       --ServerApp.ip=0.0.0.0 --ServerApp.port=8888 --ServerApp.token="$TOKEN" \
       --ServerApp.allow_origin='*' --ServerApp.allow_remote_access=True \
       --ServerApp.root_dir=/usr/src \
       >/.jupyter-runtime/server.log 2>&1 </dev/null &)
   ```
   Any existing server on `:8888` is `pkill`-ed first. `jupyterlab`/`ipykernel` come from the
   ephemeral `uv run --with` overlay — not added to any project.
5. **Create the host bridge** (only if docker-outside-of-docker is reachable):
   - Find this container's own name and its non-`traefik` Docker network.
   - Derive a proxy container name: `<repo-prefix>-jupyter-proxy` (prefix from the obt container
     name, falling back to `ti-core`). Write it to `proxy`.
   - Pick the candidate host port: `JUPYTER_BRIDGE_PORT` override → persisted `host-port` → `8888`.
   - Remove any prior proxy for this repo, then try ports `CAND..CAND+40`. For the first one that
     binds, start:
     ```bash
     docker run -d --name "$PROXY" --network "$NET" \
         -p "127.0.0.1:$p:8888" alpine/socat \
         TCP-LISTEN:8888,fork,reuseaddr "TCP:$SELF_NAME:8888"
     ```
   - On success, persist the chosen port to `host-port`.

> **Why bind the host side to `127.0.0.1` only:** the server is exposed on the host **loopback**
> exclusively — never on `0.0.0.0` — so it is not reachable from outside the machine.

## 6. How `connect.sh` works (host-side)

Run from anywhere in the repo on the **host**. Resolves repo root → `/.jupyter-runtime/`, then:

- `url` — print `http://localhost:<host-port>/?token=<token>` (bare URL on stdout for clean
  copy/paste; the Cursor hint goes to stderr). Errors if the bridge isn't ready yet.
- `status` — `curl` the host `…/api/status`; `200`/`403` ⇒ UP. Also prints the URL.
- `restart` — `task obt:devcontainer-exec -- bash /usr/src/.devcontainer/jupyter/autostart.sh`.
- `stop` — `pkill` the in-container server **and** `docker rm -f` the socat sidecar (named from
  the `proxy` file).

## 7. The kernelspecs

Each kernel launches through `uv run --project <dir> --with ipykernel`, so the kernel runs in that
project's locked environment with `ipykernel` overlaid ephemerally. Example (`ti-core-library.json`):

```json
{
  "argv": [
    "/home/om1/.local/bin/uv", "run", "--project", "/usr/src/library",
    "--with", "ipykernel",
    "python", "-m", "ipykernel_launcher", "-f", "{connection_file}"
  ],
  "display_name": "TI Core (library)",
  "language": "python"
}
```

`ti-core-backend.json` is identical except `--project /usr/src/backend` and
`"display_name": "TI Core (backend)"`.

> **`uv` path:** the kernelspecs hard-code `/home/om1/.local/bin/uv` (the `om1` remote user in this
> devcontainer). `autostart.sh` is more tolerant — it prefers `$HOME/.local/bin/uv` and falls back
> to whatever `command -v uv` finds. When replicating under a different user, update both.

## 8. Connecting from the host IDE (one-time per machine)

1. `task jupyter-url` (or `bash .devcontainer/jupyter/connect.sh url`) → copy the URL.
2. Command Palette → **Jupyter: Specify Jupyter Server for Connections** → **Existing** → paste.
   Token + port persist across rebuilds, so this is a one-time setup.
3. Open a `.py` with `# %%` cells → **Run Cell** → pick **TI Core (library)** or **TI Core (backend)**.

Requires the **Jupyter** extension in Cursor/VS Code.

## 9. Replication checklist (new repo)

1. Create `.devcontainer/jupyter/` and copy in `autostart.sh`, `connect.sh`, `README.md`,
   `SETUP.md`, and `kernels/*.json`.
2. Edit the kernelspecs: set `--project` to each importable project dir and update `display_name`.
   Verify the `uv` path matches the container's remote user.
3. In `autostart.sh`, confirm `REPO` (`/usr/src` here) matches the devcontainer `workspaceFolder`,
   and that the `cd "$REPO/<dir>"` working dir for the server launch is valid.
4. Add the `postStartCommand` to your dev `devcontainer.json` (with `|| true`).
5. Add the four `jupyter-*` tasks to `Taskfile.yml` (optional but recommended).
6. Add `/.jupyter-runtime/` to `.gitignore`.
7. Ensure the devcontainer has the **docker-outside-of-docker** feature (needed for the socat
   sidecar) — see `devcontainer.json` `features`.
8. Rebuild/start the devcontainer; run `task jupyter-status` to confirm UP; connect the IDE once.

## 10. Knobs & troubleshooting

| Symptom / need | Action |
|----------------|--------|
| Disable auto-start | Set `JUPYTER_BRIDGE_DISABLE=1` in the container env. |
| Force a specific host port | Set `JUPYTER_BRIDGE_PORT=<n>` (else first free from 8888 up). |
| "Bridge not ready yet" | Container may still be starting; `task jupyter-restart`. |
| Server not reachable | `task jupyter-status`; inspect `/.jupyter-runtime/server.log`. |
| Bridge missing | `docker ps | grep jupyter-proxy`; re-run `task jupyter-restart`. |
| Stale IDE connection after machine change | `task jupyter-url` and re-paste. |
| Multiple devcontainers | Each auto-assigns its own host port (8888, 8889, …); always use `connect.sh url`. |
