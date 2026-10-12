# cmds — 已安装命令索引与查询工具 · 设计文档

定位：扫描本机全部已安装的 CLI 命令，按来源归类（系统 / brew / 各 node 版本 / conda 各环境 / cargo / go / app 内嵌等），提供版本、描述、安装位置、安装时间的索引与交互式查询。**仅支持 macOS（Intel 与 Apple Silicon）。**

## 已确认的产品决策

1. 索引显式更新（`cmds update`），查询只读缓存；缓存过期仅提示，不自动重建。
2. 描述富化默认**离线**（只用本地元数据），联网补全（crates.io / conda 仓库）留作后续 `--net` 开关。
3. `--version` 执行探测不进默认流程；`cmds update --deep` 才跑，且仅对无本地元数据来源的命令。
4. 输出为表格 + 交互式浏览（TUI），同时提供 `--json`。
5. 仅 macOS；兼容 Intel（brew 前缀 `/usr/local`）与 M 系列（`/opt/homebrew`），两前缀并存时都索引。
6. conda 全量索引所有环境；展示层合并同环境组条目（命令 a 出现在 env1、env2 时合并展示），并提供按环境切换的 tab。
7. `app:ZCode` 这类应用内嵌工具目录算独立来源（对任意 `*.app` bundle 内的 PATH 目录泛化）。
8. 交互主界面选原型 A（Tab 浏览器），并增加**二级分类 tab**：来源有子分类时展示二级 tab（conda → 各环境、node → 各 node 版本），回答"激活该环境/该版本时有哪些命令"（升级版原型见 mockups/a-tabs.html）。
9. 索引存储用 **SQLite**（stdlib `db/sqlite`，已实测），支持高速查询；放弃 JSON 文件方案。
10. 架构采用 **Source 接口协议**：每种来源一个实现类（发现/归因/富化/子分类/展示各自定义），通过注册表装载，后续新增来源（如 fnm 独立实现、volta、mise）零核心改动。

## 来源分类学（source × origin）

发现通道有两条：**PATH 目录**（反映当前生效）与**管理器根目录**（反映机器上全部安装，不要求激活）。

| source | 发现根 | origin 标签示例 |
|---|---|---|
| system | /bin、/usr/bin、/sbin、/usr/sbin、cryptex 目录 | `system` |
| brew | `brew --prefix`（Intel `/usr/local`、M `/opt/homebrew`；并存都扫） | `brew` |
| node | 每个 node 安装本体 bin + 其 npm 全局包 bin；node 安装发现自：brew Cellar、`~/.local/share/fnm/node-versions/*/installation`、`~/.nvm/versions/node/*` | `node@brew`、`node@fnm/v22.12.0`、`node@nvm/v24.3.0`；npm 包为 `npm@fnm/v22.12.0` 等 |
| conda | `~/anaconda3`、`~/miniforge3`（+ `~/miniconda3`）的 base 与 `envs/*/bin` | `conda:miniforge3/base`、`conda:miniforge3/envs/ml` |
| cargo | `~/.cargo/bin` | `cargo` |
| pnpm | `$PNPM_HOME`（默认 macOS `~/Library/pnpm`、Linux `~/.local/share/pnpm`） | `pnpm` |
| go | `$GOPATH/bin`、$GOBIN、$GOROOT/bin（如 `/usr/local/go/bin`） | `go` |
| rvm | `~/.rvm/bin` | `rvm` |
| app | PATH 中位于 `*.app` bundle 内的目录 | `app:ZCode`（取 bundle 名） |
| manual | PATH 中其余无法归因的目录 | `manual` |

## 数据模型（SQLite，schema v1）

存储：`~/Library/Caches/cmds/index.db`（SQLite，可用 `CMDS_CACHE_DIR` 覆盖）。选择 SQLite 的理由（决策 9）：高速查询（name/source/scope 建索引）、事务原子写、增量更新空间、后续可扩展 FTS 全文检索。

```sql
create table entries (
  id           integer primary key,
  name         text not null,
  source       text not null,          -- system|brew|npm|pnpm|conda|cargo|go|rvm|app|manual
  origin       text not null,          -- 例: conda:miniforge3/envs/ml / npm@fnm/v22.12.0
  scope        text,                   -- 二级分类键：conda→环境名，npm→node 安装标识；其余为 NULL
  realpath     text not null,
  in_path      int  not null default 0,
  version      text,
  description  text,
  installed_at text,                   -- ISO8601，近似值（见下）
  size_bytes   integer,
  kind         text                    -- binary|script
);
create unique index ux_entry on entries(name, realpath);
create index ix_name on entries(name);
create index ix_source on entries(source, scope);
create table occurrences (
  entry_id integer not null references entries(id),
  path     text not null,
  path_priority int not null           -- 在 PATH 中的序号（遮蔽分析）
);
create table meta (key text primary key, value text);  -- schema_version/built_at/deep
```

- 去重键：`(name, realpath)`；同一文件经多个 PATH 目录出现合并为一个 entry 的多个 occurrence。
- `scope` 是二级 tab 的数据来源，由各 Source 实现的 `scopes()` 定义（conda → 环境、npm → node 版本；其余源无）。
- `installed_at` 一律为近似值（"安装/更新时间"）：brew 取 Cellar 版本目录 mtime，npm 取包目录 mtime，conda 取 `conda-meta/*.json` 文件 mtime，其余取文件 mtime。

## 归因与富化算法

1. **归因**：解析符号链接到真实路径 → 按真实路径前缀匹配来源根（Cellar → brew；`node_modules/<pkg>` → npm；`$PNPM_HOME` → pnpm；pipx venv → pipx…）。PATH 目录本身也做一次目录级映射（`~/.cargo/bin` → cargo）。
2. **富化（全部离线）**：brew 用 `brew list --versions` + `brew info --json=v2`（含描述）；npm 读 `node_modules/<pkg>/package.json`（name/version/description）；pnpm 读 `global/*/node_modules/<pkg>/package.json` 或包装脚本；cargo 读 `~/.cargo/.crates2.json`（bin→crate 版本）；go 用 `go version -m <二进制>` 读工具链与内嵌构建信息（不执行二进制）；conda 读 `envs/<env>/conda-meta/*.json`；系统命令描述用 `whatis`（man 数据库）。
3. **deep 探测（`--deep`）**：仅对 version 仍缺失的 entry 并行执行 `<cmd> --version|-V|version`：8 并发、单命令 2s 超时、关闭 stdin、内置跳过名单（vi/ssh/sudo/shell 类），结果写回索引。

## CLI 命令面

```
cmds                      # tty 时直接进入交互界面；非 tty 显示 help
cmds update [--deep]      # 重建索引（SQLite 事务写入）
cmds list [--source S] [--scope E] [--json] [--no-color]   # scope=环境名/node 版本标识
cmds info <name> [--json] # 单命令全字段 + 全部提供者 + 遮蔽关系
cmds which <name>         # 同名多来源 + 当前生效者（PATH 最前者）
cmds search <关键词>       # SQLite LIKE 粗筛 + 内存模糊打分排序
```

## 交互界面（TUI）规格（已定：原型 A + 二级分类 tab）

可交互原型：[mockups/a-tabs.html](mockups/a-tabs.html)（A2 版本，浏览器打开体验）。

- **一级 tab（来源）**：`All | System | Brew | Node | Conda | Cargo | Go | RVM | App | Manual`（只显示有数据的）；`Tab`/`Shift+Tab` 切换。
- **二级 tab（子分类）**：仅当来源实现了 `scopes()` 时出现——Conda → `所有环境 | miniforge3/base | miniforge3/envs/ml | …`；Node → `所有版本 | brew | fnm/v22.12.0 | fnm/v22.22.0 | nvm/v24.3.0`。`←/→`（或 `h/l`）切换，回答"**激活该环境/版本时有哪些命令**"（如 jupyter 只在 ml 环境、tsx 只在 nvm/v24.3.0）。无子分类的来源显示"该来源无二级分类"。
- `↑/↓`（或 `j/k`）移动行选择；`Enter` 进详情页（`Esc` 返回）；`/` 过滤输入；`q` 退出。
- 列：`NAME | SOURCE | VERSION | INSTALLED | DESC`（描述截断，详情页看全）。
- **同名合并**：All 视图中同一 name 的多个 entry 合并为一行（×N 徽标），SOURCE 列聚合显示各 scope；Enter 展开各提供者及 PATH 遮蔽关系。
- 非 tty 或 `--no-color` 时输出纯表格；`--json` 输出机器可读格式。

## 分期

- **P1 数据层**：发现 + 归因 + 离线富化 + 索引读写 + `list/info/which/search` + 表格/JSON 输出。全程零执行用户二进制，秒级完成。
- **P2 交互层**：TUI（tab、同名合并、详情页、过滤）。
- **P3 增强**：`--deep` 探测、whatis 描述、`dupes`/`doctor`（PATH 重复项、死目录、被遮蔽命令）、更多管理器（mise/asdf/volta/bun/pnpm/gem）按需。

## 模块规划

```
internal/model/     # Entry/Scope 等纯数据类型 + 过滤/合并纯函数
internal/scan/      # 通用目录扫描、realpath/stat 工具（无业务语义）
internal/source/    # Source 接口协议 + 注册表 + 各源实现：
                    #   system/brew/npm(含fnm,nvm发现)/conda/cargo/go/rvm/app/manual
internal/store/     # SQLite 索引读写（事务、schema 版本、过期判断）
internal/report/    # 表格与 JSON 渲染、同名合并视图
internal/ui/        # 交互 TUI（一级来源 tab + 二级 scope tab）
cmd/                # 子命令入口
```

新增一种来源 = 在 `internal/source/` 实现接口并注册，核心管道与 UI 零改动（接口定义见 ARCHITECTURE.md §3）。

## 实现前需验证的技术点

- V 0.5.2 `term` 模块 raw mode / 按键读取能力（或评估 `vlib/termui` 可用性），决定 TUI 手写 ANSI 还是基于 termui。
- 各元数据文件的真实字段：`brew info --json=v2`、`.crates2.json`、`conda-meta/*.json`、fnm 的 `installation/bin` 层级。
- `os.execute` 无超时参数，deep 探测的超时需用 spawn + channel 模式实现。
- symlink 循环防护（`os.realpath` 已处理）与权限不可读目录的容错。
