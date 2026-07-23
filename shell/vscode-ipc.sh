# shell/vscode-ipc.sh — heal a stale VSCODE_IPC_HOOK_CLI (shared by bash + zsh)
#
# Editor-server shells (VS Code / Cursor remote) export VSCODE_IPC_HOOK_CLI so
# CLI helpers — `code`, and the $BROWSER shim that things like `aws sso login`
# call — can reach the editor over a per-connection unix socket. Every editor
# reconnect creates a NEW socket and removes the old one, but tmux panes keep
# the environment they were born with, so long-lived sessions end up pointing
# at a deleted socket and every browser-open fails with
# `connect ENOENT /run/user/<uid>/vscode-ipc-<uuid>.sock`.
#
# fix_vscode_ipc repoints the variable at the newest live socket. Each rc file
# registers it to run before every prompt (zsh precmd / bash PROMPT_COMMAND),
# so shells self-heal after every editor reconnect. The newest socket can
# belong to a different editor window when several are connected — acceptable:
# any live window beats a dead socket.

fix_vscode_ipc() {
    if [ -n "${VSCODE_IPC_HOOK_CLI:-}" ] && [ ! -S "$VSCODE_IPC_HOOK_CLI" ]; then
        local sock
        sock="$(command ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/vscode-ipc-*.sock 2>/dev/null | head -n 1)"
        [ -S "$sock" ] && export VSCODE_IPC_HOOK_CLI="$sock"
    fi
    return 0
}
