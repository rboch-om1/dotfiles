# Global Instructions

## Docstrings

**When writing or modifying functions, methods, or classes, always include a comprehensive docstring** — not just a one-line description. Document `Args:` (each parameter) and `Returns:` (and `Raises:` when relevant). Match the project's existing docstring style (e.g. Google, NumPy).

**Exceptions:**
- Unit tests need only a brief one-line description of what they verify — no `Args:`/`Returns:` sections.
- Where `Args:`/`Returns:` is not standard or not appropriate (e.g. Pydantic models, dataclasses, enums), follow the conventional documentation style for that object type instead — typically a class-level description plus per-field documentation.

## Devcontainer Workflow (om1inc / om1incubator repos)

**MANDATORY: When working in any GitHub repository owned by `om1inc` or `om1incubator`, ALL pre-commit checks, commits, and shell commands that need the repo's toolchain MUST run inside the devcontainer.**

### Commands

| Step | Command | When |
|------|---------|------|
| **Build** | `task obt:devcontainer-build` | First time, or after devcontainer config changes |
| **Start** | `task obt:devcontainer-up` | Before running any in-container commands |
| **Execute** | `task obt:devcontainer-exec -- <command>` | All commits, pre-commit hooks, linting, tests, etc. |

### Examples

```bash
# Build the devcontainer
task obt:devcontainer-build

# Start the devcontainer
task obt:devcontainer-up

# Commit inside the devcontainer
task obt:devcontainer-exec -- git commit -m "feat: add widget support"

# Run arbitrary commands
task obt:devcontainer-exec -- pre-commit run --all-files
task obt:devcontainer-exec -- make test
```

### Rules

1. **Never** run `git commit` directly on the host for these repos — always use `task obt:devcontainer-exec -- git commit ...`
2. Ensure the devcontainer is running (`devcontainer-up`) before executing commands
3. Stage files on the host as normal (`git add`), then commit via devcontainer

### Checking Devcontainer Status

**Before running `task obt:devcontainer-up`, first check whether the devcontainer is already running.** Re-running `devcontainer-up` when the container is already up can produce confusing output or errors — don't mistake those for real failures.

1. Check if the devcontainer is already up (e.g. `docker ps` and look for the running devcontainer, or run a no-op via `task obt:devcontainer-exec -- true`).
2. If it is already running, **skip** `task obt:devcontainer-up` and proceed straight to `task obt:devcontainer-exec -- <command>`.
3. Only run `task obt:devcontainer-up` if the container is **not** currently running.
4. If `devcontainer-up` does emit warnings/errors because the container already exists, treat those as benign — verify the container is actually up rather than assuming the command failed.

## JIRA Ticket Creation

**When asked to open/create a JIRA ticket, follow these defaults unless explicitly instructed otherwise.**

### Defaults

| Field | Default |
|-------|---------|
| **Project** | `EX` |
| **Sprint** | The most recent **TI Sprint** |
| **Story Points** | A base estimate of `1`, `3`, `5`, or `8` based on complexity (see scale below) |
| **Assignee** | Me (the user) |
| **Epic / Parent** | A sensible **existing** Epic/Parent — categorize appropriately |

### Story Point Scale

Choose the base story points by complexity:

| Points | Complexity |
|--------|------------|
| **1** | Trivial — quick change, well understood, minimal effort |
| **3** | Small — straightforward, some effort, low uncertainty |
| **5** | Medium — moderate effort, multiple steps, some unknowns |
| **8** | Large — significant effort, high complexity or uncertainty |

### Rules

1. Always use the **EX** project unless told to use a different one.
2. Assign the ticket to the most recent **TI Sprint**.
3. Assign the ticket to **me** unless instructed to assign it to someone else.
4. **Always** categorize the ticket under a sensible Epic/Parent.
5. **Only use existing** Epics/Parents — **do not create** a new Epic/Parent unless explicitly instructed to do so.
