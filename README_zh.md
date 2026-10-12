# cmds

> **扫描、归类并检索 macOS 上所有已安装的命令行工具（CLI）。本地 SQLite 毫秒级查询，配备三级动态交互式 TUI 浏览器，以及面向 AI Agent 的环境切换与执行指引。**

[English](README.md) | [简体中文](README_zh.md)

---

## 为什么需要 cmds？

现代开发者的电脑上通常积累了成百上千个分散在不同包管理器与运行时环境中的命令行工具：

- **多套 Node 版本（fnm、nvm、brew）**：`tsc`、`claude`、`pnpm` 可能在多个 Node 版本下各装了一份。到底装了哪些版本？当前终端 `$PATH` 生效的又是哪个？
- **多套 Python / Conda 环境**：`jupyter` 到底装在 `base`、`py312` 还是 `miniforge3` 中？该如何激活对应的虚拟环境？
- **PATH 遮蔽与未知二进制**：`/usr/local/bin` 下的这个命令是谁装的、版本是多少、有没有被 `$PATH` 前方同名命令遮蔽？
- **AI Agent 智能体调用困境**：AI 编码助手经常无法准确获知本机已安装的工具命令，或者因为终端输出截断而丢失关键信息。`cmds` 能够输出零截断的绝对路径以及精确的环境激活命令（例如 `Switch Env: conda activate py312`），使智能体能够一键执行。

---

## 核心特性

- **三级分类层级架构**：
  - **一级（Ecosystem 生态）**：`node`、`python`、`go`、`rust`、`brew`、`system`、`app`、`manual`
  - **二级（Package Manager 包管理器）**：`fnm`、`nvm`、`pnpm`、`anaconda3`、`miniforge3`、`uv`、`cargo`、`go`、`brew`、`system`
  - **三级（Scope / Environment 环境与版本）**：如 Conda 环境名（`base`、`py312`）或 Node 版本（`v24.11.1`）
- **交互式 TUI 浏览器（`cmds list -i`）**：
  - 纯正 Nushell 风格双线边框美化渲染。
  - 支持多层级交互 Tab（通过 `Tab` / `Shift+Tab` 或数字键快速切换）。
  - 支持横向滑动视口与空分类自动智能折叠。
  - 根据终端高度动态分页，Header 与 Tab 栏始终吸顶。
- **智能搜索（`cmds search`，AI 与人类友好）**：
  - 支持多词组合查询与权重相关性排序。
  - **零截断设计**：完整输出全路径、版本与描述，避免因终端列宽截断导致 AI 获取残缺信息。
  - 清晰的状态标识：`[Ready in PATH]`（当前环境可用）vs `[Not in PATH]`（未在当前环境）。
  - **行动指引**：直接给出命令执行方式与一键切环境命令（如 `Switch Env: conda activate py312`、`fnm use v24.11.1`）。
  - 兼具高信噪比纯文本与面向 Agent 工具调用的结构化 `--json` 格式。
- **安全高效**：
  - **零命令执行**：索引过程只读取文件系统清单（`package.json`、`conda-meta`、`.crates2.json`）、Homebrew receipt 和二进制内嵌构建信息，绝不执行任何被扫描的命令。
  - **零网络请求**：完全离线，基于本地 SQLite 数据库（`~/Library/Caches/cmds/index.db`）。
  - **极速性能**：多目录并行扫描与批量事务写入，数秒内索引 3,500+ 条命令，查询毫秒级响应。
- **开箱即用，零 C 依赖困扰**：内置独立自包含 SQLite3 驱动，不依赖系统 `pkg-config`，在 macOS Apple Silicon（M系列芯片）与 Intel 架构下直接编译通过。

---

## 安装

### 方式一：预编译二进制（推荐）

无需任何工具链，Apple Silicon 与 Intel 芯片均可：

```sh
curl -fsSL https://github.com/Alex-hu/cmds/releases/latest/download/install.sh | bash
```

安装脚本会自动识别 CPU 架构（含 Rosetta 场景），安装前先校验 SHA-256，默认装入 `/usr/local/bin`（不可写时落 `~/.local/bin` 并提示配置 `$PATH`）。支持 `--version <tag>` 指定版本与 `--dest <dir>` 指定安装目录。

也可从 [Releases](https://github.com/Alex-hu/cmds/releases) 手动下载 `macos-arm64` / `macos-x86_64` / `macos-universal` 压缩包，解压后把 `cmds` 放进任意 `$PATH` 目录。

### 方式二：源码编译

需要 [V 语言编译器](https://vlang.io) 0.5.x，此外零依赖——SQLite 驱动已内置，`v.mod` 未声明任何外部模块：

```sh
git clone https://github.com/Alex-hu/cmds.git
cd cmds
make prod        # 等价于：v -prod -o cmds .
```

---

## 首次使用

建立初始索引（索引约 3,500 条命令仅需约 5 秒）：

```sh
cmds update      # 源码编译的用户执行 ./cmds update
```

---

## 使用指南

```
Usage: cmds [options] <command> [args]

Commands:
  update [--deep]                 重建索引
  list [--source S] [--scope E]   列出已索引命令（支持 -i 交互式 TUI 浏览器）
  search [options] <query...>     智能检索命令（支持多词与环境切换提示）
  version                         打印版本信息
  help                            显示帮助
```

全局选项：`-v, --verbose`（输出各源详细扫描统计）。

---

### 1. 智能检索（`cmds search`）

支持多词组合搜索、相关性权重打分以及针对未激活环境的操作指引：

```sh
# 基础检索（多词组合匹配）
cmds search agent
cmds search "agent browser"

# 仅查找当前 PATH 中可直接调用的命令
cmds search jupyter --in-path

# 限制返回条数
cmds search python -n 5

# 表格视图展示
cmds search jupyter --table

# 面向 AI Agent / 自动化脚本的 JSON 输出
cmds search browser-use --json
```

#### 纯文本输出示例（高信噪比、零截断）

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

#### 结构化 JSON 输出示例（`--json`）

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

### 2. 命令列表与交互式 TUI（`cmds list`）

```sh
# 启动交互式三级分类 Tab 浏览器
cmds list -i

# 按生态、包管理器或环境过滤
cmds list --ecosystem node --manager fnm --scope v24.11.1
cmds list --ecosystem python --manager anaconda3 --scope py312

# 强制输出静态无边框/边框表格
cmds list --plain
```

---

## 来源分类体系

| 生态 (Ecosystem) | 识别包管理器 (Manager) | 环境与版本示例 (Scope) | 识别依据 |
|---|---|---|---|
| `node` | `fnm`、`nvm`、`pnpm`、`brew`、`system` | `v24.11.1`、`v22.12.0` | 全局 `package.json` 清单及 Node 版本目录 |
| `python` | `anaconda3`、`miniforge3`、`miniconda3`、`uv` | `base`、`py312`、`ml` | `conda-meta/*.json` 及虚拟环境目录 |
| `rust` | `cargo` | — | `~/.cargo/.crates2.json`（自动跳过 rustup shims） |
| `go` | `go` | — | `$GOPATH/bin`，通过 `go version -m` 解析构建信息 |
| `brew` | `brew` | — | `/opt/homebrew` 与 `/usr/local` 下的 Cellar 元数据 |
| `system` | `system` | — | `/bin`、`/usr/bin`、`/sbin`、`/usr/sbin` |
| `app` | `app` | `app:Cursor`、`app:Docker` | 提取自应用程序内嵌的 CLI 工具 |
| `manual` | `manual` | — | `$PATH` 中无法归因到以上规则的自定义目录（兜底） |

---

## 本地开发与测试

```sh
# 运行全部单元测试与集成测试
v test .

# 检查代码风格与格式（保持零警告与零提示）
v fmt -w . && v vet .

# 构建优化产物
make prod
```

### 设计文档与参考资料

- [docs/HIERARCHY_3LEVEL_DESIGN.md](docs/HIERARCHY_3LEVEL_DESIGN.md) — 三级分类架构设计规范。
- [docs/SEARCH_CMD_DESIGN.md](docs/SEARCH_CMD_DESIGN.md) — `search` 检索子命令设计与 AI 友好指引规则。
- [docs/SPIKE.md](docs/SPIKE.md) — 各来源元数据实机探测分析记录。
- [AGENTS.md](AGENTS.md) — 仓库开发与工程规范。

---

## 开源协议

[MIT](LICENSE)
