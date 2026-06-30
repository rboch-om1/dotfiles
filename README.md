# dotfiles

Personal dotfiles for the **OM1 devenv** (a disposable Ubuntu/EC2 host backed by a
persistent `/mnt/devdata` EBS volume). Structured after
[`jyates-om1/dotfiles`](https://github.com/jyates-om1/dotfiles) and wired into the
[`om1inc/devenv`](https://github.com/om1inc/devenv) provisioner via the
`dotfiles_repo` / `dotfiles_script` keys in `environment.tfvars`.

On every `devenv up` / `devenv rebuild`, the provisioner clones this repo and runs
[`./setup`](./setup), which re-establishes the environment with no manual steps.

## Layout

| Path | What it is |
| --- | --- |
| `setup` | Idempotent install script the provisioner runs on every rebuild. |
| `bash/.bashrc`, `bash/.bash_profile` | Bash config: history, PATH (`~/.local/bin`, `/mnt/devdata/bin`), starship, `CLAUDE_CODE_FORCE_SYNC_OUTPUT`, aliases. |
| `docker/config.json` | Enables the ECR credential helper (`credsStore: ecr-login`). |
| `git/gitconfig_template` | Shared git config, *included* by a machine-local `~/.gitconfig` (identity stays local). |
| `tmux/.tmux.conf` | tmux: mouse, 50k scrollback, OSC-52 clipboard over SSH, vi copy-mode, browser-tab-style status bar. |
| `claude/CLAUDE.md` | Global Claude Code instructions (docstrings, devcontainer workflow, JIRA defaults). |
| `claude/scripts/*.sh` | Claude status line (context/cost/rate-limit meter) + a `SessionStart` cost-log cleanup hook. |
| `claude/settings.snippet.json` | The `statusLine` + `SessionStart` blocks `setup` merges into `~/.claude/settings.json`. |
| `scripts/clean_repos.sh` | Maintenance helper that resets `~/code` repos + Docker to a near-pristine state to reclaim disk. |

## What `setup` does

1. **Symlinks** `~/.bashrc`, `~/.bash_profile`, `~/.tmux.conf` to the tracked files
   (backing up any pre-existing real files to `*.backup`).
2. **gitconfig** — ensures `~/.gitconfig` *includes* `git/gitconfig_template` and
   sets a machine-local identity **only if none exists**. Skipped inside devcontainers.
3. **Docker** — symlinks `~/.docker/config.json` for ECR auth.
4. **Claude Code** — symlinks the two scripts into `~/.claude/scripts`, copies
   `CLAUDE.md` **only if missing** (never clobbers live edits), and merges the
   `statusLine` + cost-log `SessionStart` hook into `~/.claude/settings.json` (via
   `jq`, idempotent — other keys/hooks are preserved).
5. **clean_repos.sh** — symlinks it into `~/code` (it operates on its own directory,
   so it must live there).
6. **Best-effort installs** — `starship` and the ECR credential helper, only if absent.

### Differences from the upstream template

- Uses **this repo's own** `tmux/.tmux.conf` (no tmux plugin manager / Catppuccin),
  so there is no plugin-bootstrap step.
- **Does not change the login shell.** Bash config is shipped and applies when you
  run `bash`, but `setup` does not `chsh` (the login shell stays zsh).
- Adds the **Claude Code** and **`clean_repos.sh`** blocks, which the template doesn't have.

## Manual install / re-run

```bash
git clone https://github.com/rboch-om1/dotfiles ~/dotfiles
~/dotfiles/setup
```

Re-running is safe — every step is idempotent.

## Wiring into devenv

Add to your entry in `om1inc/devenv` → `terraform/environments/shared-services/environment.tfvars`:

```hcl
"rboch" = {
  volume_size     = 250
  dotfiles_repo   = "https://github.com/rboch-om1/dotfiles"
  dotfiles_branch = "main"
  dotfiles_script = "setup"
}
```
