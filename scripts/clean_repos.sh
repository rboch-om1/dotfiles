#!/usr/bin/env bash
#
# clean-repos.sh — reset the (transient) devenv to a near-pristine state to free disk.
#
# Run ONLY when you have no active work. For every repo in this directory it:
#   1. force-removes all git worktrees (discards any uncommitted worktree changes)
#   2. runs `git clean -xdff` — deletes node_modules, venvs, all of .devcontainer-data
#      (incl. the 50GB+ src-external external checkouts), .obt/.tasks/.env, etc.
# Then, once:
#   3. force-removes every devcontainer container EXCEPT the shared obt-traefik/dns stack
#   4. prunes orphaned networks, all unused volumes (incl. postgres/redis data), and
#      dangling images
#   5. removes every locally built vsc-* devcontainer image (incl. -uid variants)
#
# Left intact: pulled images (obt base, pgvector, node, traefik, redis, obt-mkcert),
# the obt-traefik stack, the BuildKit build cache (run `docker buildx prune` for that),
# and per-repo .notebooks/.sql_scripts/.devcontainer/jupyter directories.
#
# Usage: clean-repos.sh [--dry-run] [-y|--yes]

set -uo pipefail

CODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESERVE_PROJECTS=("obt-traefik") # compose projects to keep (shared dev stack)

DRY_RUN=false
ASSUME_YES=false
for arg in "$@"; do
    case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -y | --yes) ASSUME_YES=true ;;
    -h | --help)
        sed -n '2,21p' "$0"
        exit 0
        ;;
    *)
        echo "unknown arg: $arg" >&2
        exit 2
        ;;
    esac
done

# Echo a command, then run it unless --dry-run.
run() {
    printf '  + %s\n' "$*"
    $DRY_RUN || "$@"
}

# git clean with a useful file-level preview under --dry-run.
# Keep embedded .notebooks, .sql_scripts, and the gitignored Jupyter bridge
# (.devcontainer/jupyter — deployed by ../setup, see ../jupyter-bridge/).
CLEAN_EXCLUDES=(-e .notebooks -e .sql_scripts -e .devcontainer/jupyter)
clean_repo() {
    local r="$1"
    if $DRY_RUN; then
        printf '  + git -C %s clean -xdff %s  (preview, first 15 paths):\n' "$r" "${CLEAN_EXCLUDES[*]}"
        git -C "$r" clean -xdffn "${CLEAN_EXCLUDES[@]}" 2>/dev/null | head -15 | sed 's/^/      /'
    else
        run git -C "$r" clean -xdff "${CLEAN_EXCLUDES[@]}"
    fi
}

# --- Gather scope (read-only; safe under --dry-run) ---------------------------

# Main repos only: a real checkout has a .git *directory*; a worktree has a .git *file*.
mapfile -t REPOS < <(for d in "$CODE_DIR"/*/; do [ -d "${d}.git" ] && printf '%s\n' "${d%/}"; done)

wt_total=0
for r in "${REPOS[@]}"; do
    n=$(git -C "$r" worktree list 2>/dev/null | tail -n +2 | wc -l)
    wt_total=$((wt_total + n))
done

keep_re="$(
    IFS='|'
    echo "${PRESERVE_PROJECTS[*]}"
)"
mapfile -t RM_CONTAINERS < <(
    docker ps -a --format '{{.ID}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null |
        awk -F'|' -v keep="$keep_re" '$2!="" && $2 !~ ("^(" keep ")$") {print $1}'
)
mapfile -t VSC_IMAGES < <(docker images --filter=reference='vsc-*' -q 2>/dev/null | sort -u)

disk() { df -h "$CODE_DIR" | awk 'NR==2{print $3" used / "$2" ("$5")"}'; }

echo "clean-repos.sh — target: $CODE_DIR"
$DRY_RUN && echo "(DRY RUN — nothing will be changed)"
echo "  repos:                ${#REPOS[@]}"
echo "  worktrees to remove:  $wt_total"
echo "  containers to remove: ${#RM_CONTAINERS[@]}  (preserving: ${PRESERVE_PROJECTS[*]})"
echo "  vsc-* images to rmi:  ${#VSC_IMAGES[@]}"
echo "  disk now:             $(disk)"
echo

if ! $ASSUME_YES && ! $DRY_RUN; then
    read -r -p "This is destructive and assumes no active work. Proceed? [y/N] " ans
    [[ "$ans" == [yY] || "$ans" == [yY][eE][sS] ]] || {
        echo "Aborted."
        exit 1
    }
fi

# --- Phase 1: per-repo worktree removal + clean -------------------------------
for r in "${REPOS[@]}"; do
    [ -d "$r" ] || continue # may have been deleted as a sibling worktree
    echo "==> $r"
    # First porcelain "worktree" line is the main checkout; remove the rest.
    mapfile -t wts < <(git -C "$r" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    for ((i = 1; i < ${#wts[@]}; i++)); do
        run git -C "$r" worktree remove --force "${wts[i]}"
    done
    ((${#wts[@]} > 1)) && run git -C "$r" worktree prune
    clean_repo "$r"
done

# --- Phase 2: docker teardown -------------------------------------------------
echo "==> docker: removing devcontainers (preserving: ${PRESERVE_PROJECTS[*]})"
((${#RM_CONTAINERS[@]} > 0)) && run docker rm -f "${RM_CONTAINERS[@]}"

echo "==> docker: pruning networks, volumes (incl. db data), dangling images"
run docker network prune -f
run docker volume prune -af
run docker image prune -f

echo "==> docker: removing locally built vsc-* images"
# Recompute now that containers are gone (no-op under --dry-run).
mapfile -t VSC_IMAGES < <(docker images --filter=reference='vsc-*' -q 2>/dev/null | sort -u)
((${#VSC_IMAGES[@]} > 0)) && run docker rmi -f "${VSC_IMAGES[@]}"

echo
if $DRY_RUN; then
    echo "Done (dry run — nothing changed)."
else
    echo "Done.  disk now: $(disk)"
fi
