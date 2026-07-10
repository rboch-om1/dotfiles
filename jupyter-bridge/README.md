# Jupyter bridge — interactive `# %%` cells from host Cursor/VS Code

This lets you run plain `.py` scripts cell-by-cell (the `# %%` "Interactive Window") against
the project's real environment, **while editing in Cursor/VS Code on the host** — no `.ipynb`
files, no second/host virtualenv, and without opening your IDE _inside_ the devcontainer.

## How it works

On every devcontainer start, `postStartCommand` runs [`autostart.sh`](./autostart.sh), which:

1. Installs two named kernelspecs — **`TI Core (library)`** and **`TI Core (backend)`** — that
   launch via `uv run --with ipykernel`, so each kernel has `ipykernel` **and** the project
   importable, _without_ `ipykernel` being a project dependency.
2. Starts a Jupyter server in the container (jupyterlab pulled ephemerally via `uv run --with`).
3. Publishes it to the host via a small `socat` sidecar container (the host can't reach the
   container network directly, and the `obt` container is never modified).

The server binds inside the container and is only exposed on the host **loopback**.

### Multiple devcontainers at once

Supported. Jupyter always binds `:8888` _inside_ each container (separate network namespaces
never collide); the **host** port is auto-assigned to the first free port from `8888` up and
**persisted per-repo** in `/.jupyter-runtime/host-port`, so each devcontainer gets its own
stable port (e.g. `8888`, `8889`, …) and its own kernels (its own container + venv). Always use
`connect.sh url` to get the right URL for a given repo — don't assume `8888`.

## Connect from the host (Cursor / VS Code)

1. Get the URL (random per-repo token, stable across rebuilds; port auto-assigned per repo):
   ```bash
   task jupyter-url        # or: bash .devcontainer/jupyter/connect.sh url
   ```
2. Command Palette → **Jupyter: Specify Jupyter Server for Connections** → **Existing** → paste
   the URL. This is a **one-time** setup per machine — the token/port persist across rebuilds,
   so you won't need to redo it. (If you ever change machines or the list goes stale, run
   `task jupyter-url` again and re-paste.)
3. Open any `.py` with `# %%` cells, click **Run Cell**, and choose the **`TI Core (library)`**
   kernel (or `TI Core (backend)`). Selecting a kernel afterward needs no token.

Requires the **Jupyter** extension in Cursor/VS Code. Write scripts as `.py` with `# %%` cell
markers (see `.notebooks/` for examples, which is gitignored for personal scratch work).

## Managing it

```bash
task jupyter-url        # print the connect URL (paste into Cursor)
task jupyter-status     # reachability + URL
task jupyter-restart    # re-run autostart in the container
task jupyter-stop       # stop server + host bridge
```

(Equivalent `bash .devcontainer/jupyter/connect.sh {url,status,restart,stop}` also works.)

## Opt out

Set `JUPYTER_BRIDGE_DISABLE=1` in the container environment to skip auto-start. Force a specific
host port with `JUPYTER_BRIDGE_PORT` (otherwise the first free port from `8888` up is chosen and
persisted). Runtime state (`token`, `host-port`, `proxy`, `server.log`) lives in the gitignored
`/.jupyter-runtime/`.

Runtime token/log live in the gitignored `/.jupyter-runtime/` directory.
