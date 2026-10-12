# cmds search 子命令设计方案 (AI-Friendly Search Design)

本方案设计 `cmds search` 子命令，旨在为**人类开发者**与 **AI Coding Agent（如 Claude Code, Codex, Antigravity 等）** 提供高效、精准、具备行动指引（Actionable Guidance）的命令检索能力。

---

## 1. 背景与核心价值

### 1.1 现状与痛点
现有的 `cmds list` 主要服务于人机交互：
- **TUI 界面**：需要终端 raw mode，AI Agent 无法有效交互与读取；
- **静态表格 (`cmds list -p`)**：
  - 为了适应终端宽度，对路径 (`realpath`) 和描述 (`description`) 进行了截断（如 `/Users/alex/.../bin/very_long…`）；
  - 含有 ASCII 制表符边框（`╭──┬──╮`），浪费 LLM Context Token；
  - 缺乏**行动指引**：当命令未加入当前 `$PATH` 时，AI 无法从输出中直接获知**如何切换环境**（如 `conda activate <env>` 或 `fnm use <ver>`）或**如何用绝对路径直接调用**。

### 1.2 `cmds search` 的设计目标
1. **多词模糊检索与相关度排序**：支持 `cmds search agent` 或 `cmds search "agent browser"`，按匹配度精确排序；
2. **零信息截断 (Zero Truncation)**：完整输出真实路径、完整描述、版本号与来源溯源；
3. **环境切换与执行指引 (Actionable Guidance)**：
   - 明确标识命令是否在当前 `$PATH` 中；
   - 若不在当前 PATH，自动推导环境切换命令（如 `conda activate myenv`、`fnm use v24.11.1`）及绝对路径直接执行方式；
4. **双模输出 (Dual Output Modes)**：
   - **默认格式**：紧凑的高信噪比语义文本块（可读性极高、适合 LLM 推理上下文）；
   - **JSON 模式 (`--json`)**：标准结构化 JSON 数组，方便 AI 工具函数（MCP Tool / Function Calling）直接解析调用。

---

## 2. 命令行接口规范 (CLI Specification)

### 2.1 命令语法
```bash
cmds search [options] <query...>
```

### 2.2 典型调用示例
```bash
# 单关键词检索
cmds search agent

# 多关键词组合检索（双引号或空格分隔均可）
cmds search "agent browser"
cmds search agent browser

# 限制返回前 5 条结果（节省 AI 上下文 Token）
cmds search agent -n 5

# JSON 结构化输出（供 Agent 工具调用）
cmds search jupyter --json

# 限定仅在指定生态或包管理器中检索
cmds search python -e python -m anaconda3

# 仅查找当前环境变量 PATH 中可直接执行的命令
cmds search git --in-path
```

### 2.3 参数选项清单
| 参数 | 类型 | 默认值 | 作用与说明 |
|---|---|---|---|
| `<query...>` | 位置参数 (可多个) | 必填 | 搜索关键词（自动按空格分词进行交集/相关度检索） |
| `-n, --limit <N>` | int | `10` | 最多返回的结果数量（避免大批量结果冲垮 AI 上下文） |
| `--all` | bool | `false` | 返回所有匹配结果（相当于 `--limit 0`） |
| `--json` | bool | `false` | 以标准 JSON 数组输出结果 |
| `-e, --ecosystem <S>`| string | `""` | 仅检索指定技术栈生态（`node`, `python`, `go` 等） |
| `-m, --manager <M>`  | string | `""` | 仅检索指定包/环境管理器（`anaconda3`, `fnm`, `uv` 等） |
| `--scope <E>`        | string | `""` | 仅检索指定环境/版本（`myenv`, `v24.11.1` 等） |
| `--in-path`          | bool | `false` | 仅展示当前 PATH 中可直接调用的命令 |
| `--table`            | bool | `false` | 回退输出类似 `cmds list -p` 的人类表格视图 |

---

## 3. 检索与相关度打分算法 (Matching & Ranking)

### 3.1 分词与匹配规则
1. 对输入的 `query` 按空格拆分为 token 数组（全部小写化）：`tokens := query.to_lower().split(' ')`；
2. 检索字段覆盖：
   - 命令名 `e.name`
   - 功能描述 `e.description`
   - 所属生态 `e.ecosystem`
   - 包管理器 `e.manager`
   - 环境版本 `e.scope`
   - 溯源信息 `e.origin`
   - 真实路径 `e.realpath`
3. 默认执行 **AND 规则**：要求所有 token 都能在目标条目的不同字段中命中；若 AND 匹配结果为空，自动降级为 **OR 规则**，保证最大召回率。

### 3.2 相关度打分权重 (Relevance Scoring)
每个条目根据命中情况累加综合得分：
- **命令名完全一致**：`+1000`（如搜 `agent` 精确命中 `agent` 命令）
- **命令名前缀命中**：`+500`（如搜 `agent` 命中 `agent-browser`）
- **命令名包含关键词**：`+200`
- **功能描述包含关键词**：`+60`
- **包管理器 / Scope 包含关键词**：`+40`
- **当前 PATH 可直接执行**：`+20`（当前即可运行的命令加权靠前）

最终按得分降序排序，截取前 `--limit` 项输出。

---

## 4. 行动指引推导逻辑 (Actionable Guidance)

针对 AI Agent 规划下一步动作的需求，系统为每条搜索结果推导两个执行建议字段：

### 4.1 直接调用方式 (`how_to_run`)
- 若 `in_path == true`：直接使用命令名调用（如 `agent-browser`）；
- 若 `in_path == false`：使用真实绝对路径调用（如 `/Users/alex/anaconda3/envs/myenv/bin/jupyter`）。

### 4.2 环境切换命令 (`switch_env`)
- 若 `in_path == true`：无需切换，返回空；
- 若 `in_path == false`：根据包管理器与 scope 自动推导：
  - **Conda (anaconda3 / miniforge3 / miniconda3)** 且有环境：
    `conda activate <scope>`
  - **fnm** 且有 Node 版本：
    `fnm use <scope>`
  - **nvm** 且有 Node 版本：
    `nvm use <scope>`
  - **uv** 工具：
    `uv run <name>`（提示可通过 uv 直接运行）
  - **Go GOPATH**：
    `export PATH="$GOPATH/bin:$PATH"`
  - 其他情况：使用绝对路径，不生成切换命令。

---

## 5. 输出格式规范

### 5.1 默认文本格式 (AI & 人类兼顾，高信噪比)

```text
Found 2 commands matching "agent":

1. agent-browser (v0.38.1) [Ready in PATH]
   Ecosystem:   node
   Manager:     fnm
   Scope:       v24.11.1
   Description: Browser automation CLI for AI agents
   Execute:     agent-browser
   Realpath:    /Users/alex/.local/share/fnm/node-versions/v24.11.1/installation/bin/agent-browser

2. jupyter (v1.1.1) [Not in PATH]
   Ecosystem:   python
   Manager:     anaconda3
   Scope:       myenv
   Description: Jupyter Notebook
   Switch Env:  conda activate myenv
   Execute:     /Users/alex/anaconda3/envs/myenv/bin/jupyter
   Realpath:    /Users/alex/anaconda3/envs/myenv/bin/jupyter
```

**特点**：
- 结构清晰，每行键值对规范统一（`Execute:`, `Switch Env:`, `Description:`, `Realpath:`）；
- 路径与描述 100% 完整，绝无省略号截断；
- AI Agent 读取此输出后，能立刻决定是直接调用 `Execute`，还是先执行 `Switch Env` 切换环境。

### 5.2 结构化 JSON 格式 (`--json`)

```json
[
  {
    "name": "agent-browser",
    "ecosystem": "node",
    "manager": "fnm",
    "scope": "v24.11.1",
    "version": "0.38.1",
    "description": "Browser automation CLI for AI agents",
    "installed_at": "2026-09-22 09:04",
    "in_path": true,
    "how_to_run": "agent-browser",
    "switch_env": null,
    "realpath": "/Users/alex/.local/share/fnm/node-versions/v24.11.1/installation/bin/agent-browser"
  },
  {
    "name": "jupyter",
    "ecosystem": "python",
    "manager": "anaconda3",
    "scope": "myenv",
    "version": "1.1.1",
    "description": "Jupyter Notebook",
    "installed_at": "2025-04-01 14:00",
    "in_path": false,
    "how_to_run": "/Users/alex/anaconda3/envs/myenv/bin/jupyter",
    "switch_env": "conda activate myenv",
    "realpath": "/Users/alex/anaconda3/envs/myenv/bin/jupyter"
  }
]
```

---

## 6. 模块架构与落地步骤

1. **模型与检索扩展 (`internal/model/`)**：
   - 增加 `SearchResult` 或向 `Entry` 增加指引计算纯函数 `entry_action_guidance(e Entry) (string, ?string)`；
   - 增加带权重的多词相关度排序函数 `rank_entries(entries []Entry, query string) []Entry`。
2. **子命令实现 (`cmd/search.v`)**：
   - 实现 `search_cmd(ctx Context, args []string) !`；
   - 支持从 SQLite 缓存快速加载数据，执行内存级加权检索与截取；
   - 格式化输出文本模式与 JSON 模式。
3. **子命令路由与帮助 (`cmd/mod.v`)**：
   - 在 `commands()` 中注册 `search` 指令；
   - 在 `run()` 中分发 `search`。
4. **单测验证 (`cmd/search_test.v`, `internal/model/model_test.v`)**：
   - 验证单词、多词、大小写不敏感匹配；
   - 验证环境切换命令推导（conda, fnm, in_path）；
   - 验证 `--json` 输出合法性与 `--limit` 截断。
