# ~/.bash_profile — login shells (SSH / SSM / `exec bash -l`) read this.
# Defer everything to ~/.bashrc so interactive + login shells behave the same.
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
