# cmds

> **Index, categorize, and search all installed CLI commands on macOS with millisecond SQLite queries, an interactive 3-level TUI browser, and AI-agent friendly environment guidance.**

[English](README.md) | [简体中文](README_zh.md)

---

## Why cmds?

Modern developer workstations accumulate hundreds or thousands of CLI commands across fragmented package managers and runtimes:

- **Multiple Node Versions (fnm, nvm, brew)**: `tsc`, `claude`, and `pnpm` might be installed across 3 different Node installations. Which versions are installed? Which one is active in your current `$PATH`?
- **Multiple Python / Conda Environments**: Is `jupyter` installed in `base`, `py312`, or `miniforge3`? How do you activate the right environment?
- **PATH Shadowing & Mystery Binaries**: Who put that binary in `/usr/local/bin`? What version is it, and is it being masked by another command earlier in `$PATH`?
- **AI Agent Automation**: AI coding agents frequently struggle to identify installed CLI tools, often guessing commands or receiving truncated terminal outputs. `cmds` provides structured, actionable instructions (such as `Switch Env: conda activate py312` and absolute executable paths).

---

## Key Features

- **3-Level Taxonomy Hierarchy**:
  - **Level 1 (Ecosystem)**: `node`, `python`, `go`, `rust`, `brew`, `system`, `app`, `manual`
  - **Level 2 (Package Manager)**: `fnm`, `nvm`, `pnpm`, `anaconda3`, `miniforge3`, `uv`, `cargo`, `go`, `brew`, `system`
  - **Level 3 (Scope / Environment)**: Isolated environments or versions such as `base`, `py312`, `v24.11.1`
- **Interactive TUI Browser (`cmds list -i`)**:
  - Nushell-style border rendering.
  - Multi-level interactive tabs with keyboard navigation (`Tab` / `Shift+Tab` or numbers).
  - Horizontal viewport scrolling and automatic empty-tab collapsing.
  - Terminal-height dynamic pagination with sticky headers.
- **AI-Friendly Smart Search (`cmds search`)**:
  - Multi-word keyword search with weighted relevance ranking.
  - Zero-truncation output for full executable paths and descriptions.
  - Actionable status tags: `[Ready in PATH]` vs `[Not in PATH]`.
  - Concrete execution guidance and environment activation commands (`conda activate <env>`, `fnm use <version>`, etc.).
  - High-signal text block format or machine-readable `--json` array.
- **Safe & Fast**:
  - **Zero Command Execution**: Reads only package manifests (`package.json`, `conda-meta`, `.crates2.json`), Homebrew receipts, and Mach-O/Go build info. Never executes untrusted binaries during indexing.
  - **Zero Network Calls**: 100% offline, local SQLite database (`~/Library/Caches/cmds/index.db`).
  - **High Performance**: Parallel directory scanning and batch database writes. Indexes 3,000+ commands in seconds; queries return in milliseconds.
- **Zero C Runtime Dependencies**: Built-in self-contained SQLite3 driver without requiring system `pkg-config` setup; compiles out-of-the-box on macOS Apple Silicon (arm64) and Intel (x86_64).

---

## Installation

### Option 1 — Prebuilt binary (recommended)

No toolchain needed; works on both Apple Silicon and Intel Macs:

```sh
curl -fsSL https://github.com/Alex-hu/cmds/releases/latest/download/install.sh | bash
```

The installer detects your CPU architecture (including Rosetta), verifies the SHA-256 checksum before installing, and puts `cmds` into `/usr/local/bin` (or `~/.local/bin` with a `$PATH` hint if that is not writable). It also supports `--version <tag>` and `--dest <dir>`.

To install manually, download a tarball from [Releases](https://github.com/Alex-hu/cmds/releases) — `macos-arm64`, `macos-x86_64`, or `macos-universal` — extract it and put `cmds` anywhere on your `$PATH`.

### Option 2 — Build from source

Requires the [V compiler](https://vlang.io) 0.5.x and nothing else — the SQLite driver is vendored and `v.mod` declares zero external dependencies:

```sh
git clone https://github.com/Alex-hu/cmds.git
cd cmds
make prod        # equivalent to: v -prod -o cmds .
```

---

## First Run

Build the initial index (takes ~5 seconds for ~3,500 commands):

```sh
cmds update      # or ./cmds update if you built from source
```

---

## Usage

```
Usage: cmds [options] <command> [args]

Commands:
  update [--deep]                 Rebuild command index
  list [--source S] [--scope E]   List indexed commands (supports -i interactive TUI)
  search [options] <query...>     Intelligent search with environment switching guidance
  version                         Print version information
  help                            Show help
```

Global options: `-v, --verbose` (detailed scanning/enrichment statistics).

---

### 1. Smart Search (`cmds search`)

Search for commands with multi-word queries, relevance ranking, and environment guidance:

```sh
# Basic search
cmds search agent
cmds search "agent browser"

# Restrict to commands directly executable in current PATH
cmds search jupyter --in-path

# Limit number of results
cmds search python -n 5

# Table view
cmds search jupyter --table

# JSON output for AI agents / scripts
cmds search browser-use --json
```

#### Search Output Example (Human & AI Friendly)

```text
$ cmds search jupyter
Found 2 command(s) matching "jupyter":

1. jupyter (v5.3.0) [Ready in PATH]
   Ecosystem:   python / anaconda3 (scope: base)
   Description: —
   Execute:     jupyter
   Realpath:    /Users/alex/anaconda3/bin/jupyter

2. jupyter [Not in PATH]
   Ecosystem:   python / anaconda3 (scope: py312)
   Description: —
   Switch Env:  conda activate py312
   Execute:     /Users/alex/anaconda3/envs/py312/bin/jupyter
   Realpath:    /Users/alex/anaconda3/envs/py312/bin/jupyter
```

#### Structured JSON Output Example (`--json`)

```json
[
  {
    "name": "jupyter",
    "ecosystem": "python",
    "manager": "anaconda3",
    "scope": "py312",
    "version": "",
    "description": "",
    "installed_at": "",
    "in_path": false,
    "how_to_run": "/Users/alex/anaconda3/envs/py312/bin/jupyter",
    "switch_env": "conda activate py312",
    "realpath": "/Users/alex/anaconda3/envs/py312/bin/jupyter"
  }
]
```

---

### 2. List & Interactive TUI (`cmds list`)

```sh
# Launch interactive 3-level tab browser
cmds list -i

# Filter by ecosystem, manager, or environment
cmds list --ecosystem node --manager fnm --scope v24.11.1
cmds list --ecosystem python --manager anaconda3 --scope py312

# Output static plain Nushell table
cmds list --plain
```

---

## Taxonomy Matrix

| Ecosystem | Managers Detected | Scope / Environment Example | Detection Source |
|---|---|---|---|
| `node` | `fnm`, `nvm`, `pnpm`, `brew`, `system` | `v24.11.1`, `v22.12.0` | Global `package.json` manifests & node version directories |
| `python` | `anaconda3`, `miniforge3`, `miniconda3`, `uv` | `base`, `py312`, `ml` | `conda-meta/*.json` & environment directories |
| `rust` | `cargo` | — | `~/.cargo/.crates2.json` (shims filtered) |
| `go` | `go` | — | `$GOPATH/bin` with `go version -m` embedded build info |
| `brew` | `brew` | — | `/opt/homebrew` & `/usr/local` Cellar metadata |
| `system` | `system` | — | `/bin`, `/usr/bin`, `/sbin`, `/usr/sbin` |
| `app` | `app` | `app:Cursor`, `app:Docker` | Executables embedded in macOS `.app` bundles |
| `manual` | `manual` | — | Remaining custom directories in `$PATH` |

---

## Development

```sh
# Run all unit and integration tests
v test .

# Format and vet code (enforces zero warnings and zero notices)
v fmt -w . && v vet .

# Build release binary
make prod
```

### Documentation & Design References

- [docs/HIERARCHY_3LEVEL_DESIGN.md](docs/HIERARCHY_3LEVEL_DESIGN.md) — 3-Level classification architecture design.
- [docs/SEARCH_CMD_DESIGN.md](docs/SEARCH_CMD_DESIGN.md) — Search command specifications and AI guidance rules.
- [docs/SPIKE.md](docs/SPIKE.md) — Real-world CLI metadata spike reports.
- [AGENTS.md](AGENTS.md) — Workspace coding standards and V guidelines.

---

## License

[MIT](LICENSE)
