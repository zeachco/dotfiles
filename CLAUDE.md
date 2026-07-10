# CLAUDE.md

This repository is managed by a dependency-free Rust CLI. Read `AGENTS.md` for
the architecture, invariants, and verification commands.

Do not reintroduce interactive-shell logic into `setup.sh`. Package/config
policy belongs in TOML manifests, complex actions belong in typed Rust code,
and Bash/Zsh/Fish files are generated outputs.
