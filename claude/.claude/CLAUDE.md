# Python: always use `uv`, never bare `pip` / `python`

`uv` is installed. For ALL Python work use `uv` (drop-in for pip/python) —
bare `pip`/`python`/`python3` pollute the system and are blocked by a
PreToolUse hook. Quick rule: ad-hoc task → `uv run --with <pkg> script.py`;
project → `uv add <pkg>`. For the full playbook (projects, CLI tools, Python
versions, PEP 723) invoke the `uv-python` skill.

# Diagrams: default to Mermaid

Pick the format by whether the destination renders Mermaid:

- **Terminal / our Claude Code conversation** (doesn't render Mermaid) — draw
  diagrams as ASCII art so I can read them inline.
- **Anywhere that renders Mermaid** (Markdown notes, docs, READMEs) — use
  Mermaid. It expresses structure as explicit text, so it's faithful both
  rendered for humans and read back as AI context.

A nested Markdown list or table is fine in either place when it fits the data
better than a diagram.

# Search: prefer `rg` and `fd` in Bash

`rg` (ripgrep) and `fd` are installed and are the default for Bash searches —
they're faster and respect `.gitignore`.
- Search file contents: `rg pattern` instead of `grep -r` / `grep -rn`.
- Find files by name/path: `fd pattern` instead of `find . -name`.
- Pipe filtering (`... | grep foo`) and `find` with `-exec`/`-delete`/`-newer`
  or complex predicates are fine to keep as-is — `rg`/`fd` don't cover those.
