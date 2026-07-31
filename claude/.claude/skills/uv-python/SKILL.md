---
name: uv-python
description: The uv playbook for ALL Python work on this machine — installing packages, running scripts/tools, creating environments, managing Python versions. Use whenever about to install a Python dependency, run a .py script, set up a Python project, or when a bare `pip`/`python` command was just blocked. Covers ad-hoc tasks (uv run --with), real projects (uv add), CLI tools (uvx), and interpreter versions.
---

# uv playbook

`uv` is installed on this machine. For ALL Python work, use `uv`. Never run
bare `pip`, `pip3`, `python`, or `python3` — they pollute the system
environment and leave unreproducible state. A PreToolUse hook blocks bare
`pip install`; this skill is the full guidance for what to do instead.

## Pick the mode

### 1. One-off / ad-hoc tasks — the default

Editing a `.pptx`, processing a CSV, scraping a page, quick data crunching —
do NOT create a project. Use ephemeral dependencies:

- Run with temporary deps:
  `uv run --with python-pptx --with pandas script.py`
  Packages go into a cached, throwaway environment. Nothing installed
  globally; nothing to clean up; cache makes reruns instant.
- Inline a one-liner without a file:
  `uv run --with requests - <<'EOF' ... EOF`
- If the script will be kept, prefer PEP 723 inline metadata so it is
  self-contained — then just `uv run script.py`:
  ```python
  # /// script
  # dependencies = ["python-pptx", "pandas"]
  # ///
  ```

### 2. Real projects — a directory you'll keep working in

If the working dir has (or should have) a `pyproject.toml`:

- New project: `uv init`
- Add / remove deps: `uv add <pkg>` / `uv remove <pkg>`
  (updates `pyproject.toml` + `uv.lock`)
- Install/refresh env from lockfile: `uv sync`
- Re-lock: `uv lock`
- Run inside the project env: `uv run <script>.py`, `uv run pytest`,
  `uv run ruff check`, `uv run mypy`; REPL: `uv run python`
- Never `pip install` into a project — it bypasses the lockfile.

### 3. Standalone CLI tools (ruff, black, httpie, yt-dlp, …)

- Run once without installing: `uvx ruff check .`
- Install persistently for the user: `uv tool install ruff`
- List / upgrade: `uv tool list`, `uv tool upgrade --all`

### 4. Python interpreter versions

- Install a version: `uv python install 3.12`
- Pin one for a project: `uv python pin 3.12`
- List: `uv python list`

## Rules

- Default to mode 1 (`uv run --with`) for miscellaneous tasks. Only create a
  project (mode 2) when there is a clear ongoing project.
- About to type `pip install`? Stop — use `uv run --with` or `uv add`.
- Need true pip semantics inside uv: `uv pip install <pkg>` (allowed).
- If `uv` is somehow missing, install via the official installer, not pip.
