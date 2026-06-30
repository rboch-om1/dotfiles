# ~/.bashrc — OM1 devenv (managed by the dotfiles repo; symlinked by ./setup)

# If not running interactively, do nothing.
case $- in
    *i*) ;;
      *) return;;
esac

# ---- History --------------------------------------------------------------
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth          # drop duplicate lines and lines starting with a space
HISTTIMEFORMAT='%F %T '         # timestamp each entry
shopt -s histappend             # append to history, don't clobber it
shopt -s cmdhist                # store multi-line commands as a single entry
# Flush each command to the history file immediately so parallel shells
# (e.g. several tmux panes / devcontainer sessions) share one history.
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

# ---- Shell options --------------------------------------------------------
shopt -s checkwinsize           # keep $LINES/$COLUMNS right after a resize
shopt -s globstar 2>/dev/null   # ** matches files recursively
shopt -s autocd 2>/dev/null     # type a dir name to cd into it

# ---- PATH -----------------------------------------------------------------
# uv tools, starship, and other user binaries land in ~/.local/bin on the devenv.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Durable CLI tools live on the persistent /mnt/devdata volume (survives rebuilds,
# unlike snaps / ~/.local which sit on the disposable root FS). e.g. glow.
case ":$PATH:" in
    *":/mnt/devdata/bin:"*) ;;
    *) export PATH="/mnt/devdata/bin:$PATH" ;;
esac

# ---- Colors / pager -------------------------------------------------------
export CLICOLOR=1
export LESS='-FRX'              # quit if one screen, keep colors, no init clear
command -v dircolors >/dev/null 2>&1 && eval "$(dircolors -b)"

# ---- Claude Code ----------------------------------------------------------
# Force synchronized output (DEC private mode 2026) so each TUI frame is drawn
# atomically. tmux 3.4+ supports 2026 but Claude Code doesn't auto-detect it
# under tmux, so without this the animated status line tears and bleeds across
# split panes over a laggy SSM/SSH link.
export CLAUDE_CODE_FORCE_SYNC_OUTPUT=1

# ---- Aliases --------------------------------------------------------------
alias ls='ls --color=auto'
alias ll='ls -alhF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# ---- Bash completion ------------------------------------------------------
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# ---- Starship prompt ------------------------------------------------------
# Uses starship's default config. To customize, drop a ~/.config/starship.toml
# (or track one in this repo and symlink it from ./setup).
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"

# ---- Machine-local overrides (NOT tracked in the dotfiles repo) -----------
[ -f "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"
