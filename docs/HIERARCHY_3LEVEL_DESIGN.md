# 三级生态层级架构设计方案 (3-Level Hierarchy Design)

本方案旨在将 `cmds` 现有的两级分类模型升级为更符合开发者心智的**三级动态层级结构**，统一插件接口协议、数据模型、存储层及交互层。

---

## 1. 背景与目标

### 1.1 现状与痛点
在现行架构中，分类模型为两级：
- **一级 (Source)**: `npm`, `pnpm`, `conda`, `brew`, `cargo`, `go`, `system`, `manual`, `app` 等平铺展示。
- **二级 (Scope)**: 仅个别源（如 `conda` 的各个 env、`npm` 的各个 node 版本）具备二级子环境。

**存在的问题**：
1. **概念错位**：Node、Python、Go 属于编程语言/技术栈生态；而 `fnm`、`nvm`、`pnpm`、`conda`、`pipx` 是包或环境管理器；`node`、`pnpm` 并不是同级对等的源，平铺在同一级导致顶层 Tab 杂乱。
2. **缺乏管理器分类**：Node 生态下可能有 `fnm`（管理多个 node 版本及全局包）、`nvm` 以及独立的 `pnpm`；如果将它们混在一级或二级，用户无法清晰按“生态 -> 管理器 -> 环境”层层下钻。
3. **接口扩展性受限**：若未来引入 Python 的 `uv`、`pipx` 或 JavaScript 的 `bun`，如果不确立“生态”与“管理器”的层级关系，平铺的一级 Tab 将迅速膨胀失控。

### 1.2 改造目标
1. **心智模型归一**：建立标准三级层级：
   - **Level 1 (生态 Ecosystem)**：技术栈/系统领域（如 `Node`, `Python`, `Go`, `Rust`, `Homebrew`, `System`, `App`, `Manual`）
   - **Level 2 (管理器 Manager)**：具体包或环境管理器（如 `fnm`, `nvm`, `pnpm`, `conda`, `uv`, `cargo`, `go`, `brew`）
   - **Level 3 (环境/版本 Scope)**：特定管理器下的独立版本或环境（如 `v24.11.1`, `base`, `ml_env`；无子环境则为空）
2. **动态自适应展现**：不同技术栈天然具备不同的层级深度：
   - 复杂生态（如 Node、Python）：支持 1、2、3 级完整下钻；
   - 简单生态（如 Rust、Homebrew）：无三级环境，自动折叠三级 Tab 行；
   - 扁平分类（如 System、Manual）：无二级和三级，自动折叠二级与三级行；
   - 折叠释放的终端行高**动态返还给数据表格**，自适应扩充单屏条目容量 (`page_size`)。
3. **按键规范一致**：
   - `Tab` / `Shift+Tab`：切换一级生态
   - `[` / `]`：切换二级管理器
   - `←` / `→`：切换三级环境/版本
   - `↑` / `↓`：浏览表格数据
   - `PgUp` / `PgDn`：翻页浏览

---

## 2. 统一接口协议与契约设计

### 2.1 协议层（`internal/source/protocol.v`）

将 `Source` 明确定义为**包/环境管理器**维度的插件，每个插件声明其所属的一级生态 (`ecosystem`)、自身唯一标识 (`id` / manager)、展示名称以及它所提供的三级环境列表 (`scopes`)。

```v
module source

import internal.model

// Scope 是三级分类：具体环境或版本标识。
pub struct Scope {
pub:
	id    string // 例: 'v24.11.1'、'base'、'miniforge3/envs/ml'
	label string // 展示名
}

// Attribution 是归因结果，升级为显式三级字段。
pub struct Attribution {
pub:
	ecosystem string // 一级生态: 'node', 'python', 'go', 'rust', 'brew', 'system', 'app', 'manual'
	manager   string // 二级管理器: 'fnm', 'nvm', 'pnpm', 'conda', 'cargo', 'brew', 'system'
	scope     string // 三级分类键；空串=无子分类
	origin    string // 精确来源说明，例: 'conda:miniforge3/envs/ml', 'fnm:v24.11.1', 'pnpm:global'
}

// Source 是包/环境管理器维度的插件协议。
pub interface Source {
	// ecosystem 返回所属的一级技术栈生态。
	ecosystem() string
	// id 返回二级管理器唯一标识（作为 manager 键）。
	id() string
	// label 返回管理器展示名（二级 tab 文案）。
	label() string
	// roots 返回本源发现目录绝对路径。
	roots() []string
	// attribute 归因判断。
	attribute(realpath string) ?Attribution
	// enrich 就地富化元数据。
	enrich(mut entries []model.Entry) !
	// scopes 返回三级环境/版本列表；无子分类返回空数组。
	scopes() []Scope
	// priority 归因轮询优先级。
	priority() int
}
```

### 2.2 数据模型层（`internal/model/model.v`）

升级 `Entry` 结构体，显式支持三级结构：

```v
pub struct Entry {
pub mut:
	name         string
	ecosystem    string // 一级技术栈 (node|python|go|rust|brew|system|app|manual)
	manager      string // 二级管理器 (fnm|nvm|pnpm|conda|cargo|go|brew|system|app|manual)
	scope        string // 三级环境/版本 (v24.11.1|base|ml...，空串代表无子环境)
	origin       string // 溯源详情，例: conda:miniforge3/envs/ml
	realpath     string
	occurrences  []Occurrence
	in_path      bool
	version      string
	description  string
	installed_at string
	size_bytes   u64
	kind         string // binary|script
}
```

同时提供多维度聚合过滤纯函数：
- `filter_by_ecosystem(entries []Entry, eco string) []Entry`
- `filter_by_manager(entries []Entry, mgr string) []Entry`
- `filter_by_scope(entries []Entry, scope string) []Entry`

---

## 3. 存储层演进（SQLite Schema v2）

升级 `internal/store/store.v` 的版本号至 `schema_version = 2`。

```sql
create table entries (
    id            integer primary key,
    name          text not null,
    ecosystem     text not null,
    manager       text not null,
    scope         text,
    origin        text not null,
    realpath      text not null,
    in_path       integer not null default 0,
    version       text,
    description   text,
    installed_at  text,
    size_bytes    integer,
    kind          text
);

create unique index ux_entry on entries(name, realpath);
create index ix_name on entries(name);
create index ix_hierarchy on entries(ecosystem, manager, scope);
```

> **平滑迁移保障**：
> `store.open()` 内置版本对比逻辑：当 `user_version != schema_version` 时，自动调用 `drop_all` 并执行 `create_schema`。升级代码后，用户首次运行 `cmds update` 时将全自动完成数据库结构重建与数据归因入库，对用户无感知、无破坏。

---

## 4. 各来源（Source）的层级映射全景

| 一级 Ecosystem (生态) | 二级 Manager (管理器) | 三级 Scope (环境/版本) | 发现路径与典型工具 |
|---|---|---|---|
| **Node** | `fnm` / `npm` | 各 Node 版本 (`v24.11.1` 等) | `~/.local/share/fnm/current/bin` (node, npm, tsc) |
| **Python** | `anaconda3` / `miniforge3` / `miniconda3` | 各环境 (`base`, `myenv`, `omni`, `py312` 等) | `~/anaconda3/bin`, `~/miniforge3/bin`, `~/anaconda3/envs/*` |
| **Python** | `uv` | 工具与工具链 (`tools`, `toolchain`) | `~/.local/share/uv/tools/*`, `~/.local/share/uv/python/*`, `~/.local/bin` |
| **Go** | `go` | `toolchain`, `gopath` | `$GOROOT/bin`, `$GOPATH/bin` (go, gofmt, air) |
| **Rust** | `cargo` | *(无，自动折叠)* | `~/.cargo/bin` (cargo, rustc, ripgrep) |
| **Homebrew** | `brew` | *(无，自动折叠)* | `/opt/homebrew/bin` (git, ffmpeg, curl) |
| **System** | `system` | *(无，自动折叠)* | `/usr/bin`, `/bin` (ls, grep, awk) |
| **App** | `app` | *(无，自动折叠)* | GUI 应用命令行暴露目录 (code, subl) |
| **Manual** | `manual` | *(无，自动折叠)* | 用户自定义脚本目录 |

---

## 5. 动态 TUI 与自适应高度计算

### 5.1 行高占用规则
TUI 界面各区域行高分配如下：
- **标题栏 (Banner)**: 1 行
- **一级生态 Tab (Level 1)**: 1 行（支持滑动视口与 `◀ ▶` 指示器）
- **二级管理器 Tab (Level 2)**: 
  - 当当前生态下有 `> 1` 个管理器，或管理器有明确子项时展示（1 行）
  - 否则**完全折叠（0 行）**
- **三级环境/版本 Tab (Level 3)**:
  - 当当前选中的管理器下有 `> 1` 个三级环境时展示（1 行）
  - 否则**完全折叠（0 行）**
- **搜索输入行**: 1 行
- **表格边框与表头**: 3 行（顶框 1 + 列标题 1 + 中分线 1）
- **表格底框**: 1 行
- **底栏状态与按键提示**: 1 行

### 5.2 动态 page_size 计算
```v
fixed_overhead := 1 /*banner*/ + 1 /*L1*/ +
                  (if show_l2 { 1 } else { 0 }) +
                  (if show_l3 { 1 } else { 0 }) +
                  1 /*search*/ + 3 /*table_head*/ + 1 /*table_bot*/ + 1 /*footer*/

page_size := if rows > fixed_overhead + 2 {
    rows - fixed_overhead
} else {
    1
}
```
- **Node / Python 等满级状态**: `fixed_overhead = 10`，表格使用 `rows - 10`。
- **Go 等二级状态**: `fixed_overhead = 9`，表格使用 `rows - 9`（多得 1 行）。
- **Rust / System 等扁平状态**: `fixed_overhead = 8`，表格使用 `rows - 8`（多得 2 行）。

切换 Tab 时，系统实时动态重算 `page_size` 并做分页截取，彻底保证屏幕顶栏固定、底栏固定、绝不溢出或跳动。

---

## 6. 实施路线图

1. **第 1 步：接口协议与模型升级**
   - 修改 `internal/source/protocol.v`（`Attribution` 与 `Source` 增加 `ecosystem()`）。
   - 修改 `internal/model/model.v`（`Entry` 增加 `ecosystem`、`manager`，调整过滤逻辑）。
   - 修改 `internal/store/store.v`（升级 `schema_version = 2`，更新 insert/query 语句）。
   - 更新 `store_test.v` 与 `model_test.v`。

2. **第 2 步：各 Source 适配三级归因**
   - 适配 `simple_sources.v`（system, brew, app, manual, rvm）。
   - 适配 `heavy_sources.v`（npm/fnm, pnpm, conda, go, cargo）。
   - 更新全部相关单元测试（`simple_sources_test.v`, `heavy_sources_test.v`）。

3. **第 3 步：更新管道与命令行查询**
   - 修改 `cmd/update.v`（使用新的 `attr.ecosystem` 与 `attr.manager` 组装 `Entry`）。
   - 修改 `cmd/list.v`（支持按 `--ecosystem` 和 `--manager` 多维过滤）。

4. **第 4 步：TUI 交互与渲染引擎重构**
   - 改造 `internal/ui/app.v`：
     - `AppState` 升级：引入 `ecosystems`, `active_eco_idx`, `managers`, `active_mgr_idx`, `scopes`, `active_scope_idx`；
     - 增加 `[` / `]` 处理管理器切换，`←` / `→` 处理环境切换；
     - 动态计算三级联动选项列表与命令计数。
   - 改造 `internal/ui/render.v`：
     - 实现 Level 2 与 Level 3 的动态折叠判定与渲染；
     - 动态计算 `fixed_overhead` 与 `page_size`；
     - Nushell 表格 SOURCE 列升级显示为 `ECO/MGR` 或友好组合标签；
     - 详情弹窗展示完整的生态、包管理器、环境路径。

5. **第 5 步：验证与回归**
   - 运行 `cmds update` 重建全量索引库。
   - 运行 `make test` 确保全部单测通过。
   - 运行 `make vet` 保证 0 warning / 0 notice。
   - 终端实测多技术栈交互表现。
