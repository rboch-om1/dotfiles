# ~/.zshrc — OM1 devenv (managed by the dotfiles repo; symlinked by ./setup)
#
# Interactive-zsh config. Deliberately minimal: zsh is the devenv's stock login
# shell and stays close to defaults (the fuller custom setup lives in bash/).
# Locale lives in zsh/.zshenv so non-interactive shells get it too.

# uv's PATH shim (~/.local/bin). The uv installer appends this line to the real
# ~/.zshrc it finds; setup replaces that file with this symlink, so source it
# here (guarded — the shim may not exist yet on a fresh provision).
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Heal a stale editor-server IPC socket before every prompt — rationale in
# shell/vscode-ipc.sh. Resolve the repo from this file's own symlink so the
# repo can live anywhere.
if [ -f "$(dirname "$(readlink -f "$HOME/.zshrc")")/../shell/vscode-ipc.sh" ]; then
    . "$(dirname "$(readlink -f "$HOME/.zshrc")")/../shell/vscode-ipc.sh"
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd fix_vscode_ipc
fi

# ---- Machine-local overrides (NOT tracked in the dotfiles repo) -----------
[ -f "$HOME/.zshrc.local" ] && . "$HOME/.zshrc.local"
