# ~/.zshenv - OM1 devenv (managed by the dotfiles repo; symlinked by ./setup)
#
# Sourced by EVERY zsh (login, interactive, scripts), so this is the one place
# that can guarantee a UTF-8 locale even in shells spawned with a stripped
# environment (editor-server terminals, provisioning hooks). Without LANG the
# shell falls back to the POSIX locale and multibyte output/copy paths mangle
# (em dash -> "a"-mojibake).
case "${LANG:-}" in
    *.UTF-8 | *.utf8) ;;
    *) export LANG=C.UTF-8 ;;
esac
