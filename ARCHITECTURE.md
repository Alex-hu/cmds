# cmds · 代码架构设计

配套文档：[DESIGN.md](DESIGN.md)（产品需求与决策）· [PLAN.md](PLAN.md)（开发计划）· [mockups/](mockups/index.html)（交互原型）。本文回答"代码怎么组织、模块怎么依赖、关键机制怎么实现"。

## 0. 技术选型与依赖管理（实测于本机 V 0.5.2）

**依赖管理策略：允许按需引入第三方依赖，优先选用质量可靠、活跃维护的第三方库或标准库。**

依赖分层机制：
1. **V 模块依赖（包管理器 vpm）**：第三方 V 依赖在根目录 `v.mod` 中显式声明（`dependencies: [...]`，类似 Java Maven 的 `pom.xml`），克隆项目后运行 `make deps` 或 `v sync` 自动下载与还原。
2. **系统原生构建依赖（System Prerequisites）**：V 直接编译为机器码，底层与系统 C 库（如 `sqlite3`）对接；macOS 下依赖 `pkg-config` 提供头文件与链接元数据。通过 `Makefile` 的 `check-deps` 目标在构建前自动化预检，杜绝隐式缺失。

现有核心选型依据：

| 需求 | 选型 | 实测结论 |
|---|---|---|
| 参数/子命令 | stdlib `flag` | 已在骨架中验证；`vlib/cli`（Commander 式）子命令分发可用但自动 `--help` 实测报错（README 与实现不符），暂不用 |
| 索引存储 | stdlib `db/sqlite` + 系统 `sqlite3` | **全链路实测通过**：`sqlite.connect(path)!` → DDL → `exec_param_many` 参数化写入 → `exec`/`q_int` 查询。坑：`connect` 结果需声明 `mut` 才能调用 `close()`；macOS 下需安装 `pkg-config` 协助编译器获取头文件；`json` 模块已被移除（`--json` 输出在渲染层手写序列化或用 `json2`） |
| 接口协议 | V `interface` | 实测通过：`[]Source` 异构集合 + 动态分发 + `?string` Option 返回的方法签名均可用 |
| 终端控制 | stdlib `term` | 颜色/终端尺寸/按键读取（`term.key_pressed`、`term.utf8_getchar`）齐备 |
| TUI 框架 | **手写 ANSI 视图循环** | `term/ui`（termui）在本版本仅剩核心单文件、组件缺失；`ncurses` 引 C 依赖过重。手写可控且需求有限（单屏表格 + 弹层/分栏） |
| 模糊匹配 | 自实现（~80 行） | vpm 无像样的模糊匹配库（[vpm 搜索](https://vpm.vlang.io)、[awesome-v](https://github.com/vlang/awesome-v) 均无）；fzf 式子序列打分算法简单 |
| 进度显示 | 自实现（~30 行） | vpm 无维护中的 progress/spinner 库；`update` 用单行计数器即可 |
| 并发 | stdlib `spawn`/`sync` | 无需第三方 |
| 正则/字符串 | stdlib `regex`、`strings` | 足够 |

引入第三方库的原则：优先评估其维护活跃度、是否有 CI/测试、无侵入性。确认引入时写入 `v.mod`。

## 1. 分层与模块依赖

```
cmd/                    子命令入口（update/list/info/which/search/browse）
  │
  ├─► internal/report/      纯文本表格 + JSON 渲染、同名合并视图
  ├─► internal/ui/          交互 TUI（读 report 的视图模型，手写 ANSI）
  │
  ├─► internal/store/       SQLite 索引读写（事务、schema 版本、过期提示）
  │
  └─► internal/source/      ★ Source 接口协议 + 注册表 + 各源实现
        │                     source/system.v  brew.v  npm.v  conda.v
        │                     cargo.v  go.v  rvm.v  app.v  manual.v
        │                     （npm.v 内含 brew/fnm/nvm 三种 node 安装发现）
        ▼
      internal/scan/        通用目录扫描、realpath/stat/exec 工具（无业务语义）
        ▼
      internal/model/       Entry/Scope/Index 等纯数据类型 + 过滤/合并纯函数
```

**import 规则（强制，vet 不可查，靠约定与 review）**：

- `model` 不 import 任何内部模块（纯类型 + 纯函数）。
- 依赖只能向下：`cmd → report/ui / store / source → scan → model`。
- `source` 的各实现之间**互不依赖**（都只依赖 scan/model）；`source` 不依赖 `store`；`ui` 不直接写 `store`（写索引只发生在 `cmd/update` 管道里）。
- `report` 与 `ui` 共享 `model` 里的视图类型（如 `Row`/`MergedEntry`），UI 不重复实现合并逻辑。

## 2. 核心数据流

### update 管道（写，registry 驱动）

```
source.registry() ──► 对每个注册的 Source 实现：
   │   roots()    发现本源全部根（可多个：anaconda3+miniforge3、brew 双前缀、fnm/nvm 各版本）
   ▼
   scan.roots（spawn 并行扫各根目录）
   │  每个文件: name + dir + realpath(os.realpath) + stat(mtime/size/kind)
   ▼
   source.attribute(realpath) ?(source, origin, scope)   ← 归因，返回 none 则轮询下一个源
   ▼
   dedupe：key=(name, realpath)，合并 occurrences[{path, path_priority}]
   ▼
   source.enrich(mut entries)（并行，只读各源自己的元数据）：
   │   brew → brew list --versions + brew info --json=v2
   │   npm  → node_modules/<pkg>/package.json（逐 node 安装）
   │   cargo→ ~/.cargo/.crates2.json
   │   go   → go version -m <file>（不执行二进制）
   │   conda→ envs/<env>/conda-meta/*.json（逐环境）
   │   其余 → 无（version 留空，deep 模式再补）
   ▼
   store.save（SQLite：单事务 DELETE+INSERT 或 UPSERT，PRAGMA user_version 管 schema 版本）
```

### 查询管道（读）

```
store.query(SQL 过滤: source/scope/name) ──► model.merge_by_name() / fuzzy 打分
        ──► report.render_table / render_json
        ──► ui.run(event_loop)
```

搜索策略：`name LIKE '%q%'` 走 `ix_name` 粗筛 → 内存 fzf 式子序列打分排序（数据量 < 数万条，内存排序微秒级）。FTS5 全文检索作为后备增强，需先实测系统 libsqlite3 是否启用 FTS5（列入 M1 spike）。

## 3. Source 接口协议（本架构的核心扩展点）

每种来源一个实现 struct，实现统一接口并注册。**新增来源 = 新文件 + 注册一行，核心管道与 UI 零改动。** 以下接口签名已在本机 V 0.5.2 实测编译通过（含动态分发与 Option 返回）：

```v
// source/protocol.v
pub struct Scope {
pub:
	id    string   // 二级 tab 键：'miniforge3/envs/ml'、'fnm/v22.12.0'
	label string   // 展示名
}

pub struct Attribution {
pub:
	source string   // 'conda'
	origin  string   // 'conda:miniforge3/envs/ml'
	scope   ?string // 二级分类键；无子分类的源返回 none
}

pub interface Source {
	id() string                          // 源标识（一级 tab 键）
	label() string                       // 展示名（一级 tab 文案）
	roots() []string                     // 本源全部发现根（绝对路径）
	attribute(realpath string) ?Attribution   // 归因；不属于本源返回 none
	enrich(mut entries []model.Entry) !  // 就地填充 version/description/installed_at
	scopes() []Scope                     // 二级分类（conda→环境，npm→node 版本；无则空）
	priority() int                       // 归因轮询顺序（越具体越先，如 npm 先于 manual）
}

// source/registry.v
pub fn registry() []Source {
	return [NpmSource{}, CondaSource{}, BrewSource{}, CargoSource{}, GoSource{},
		RvmSource{}, AppSource{}, SystemSource{}, ManualSource{}]
}
```

各源实现要点：

- **npm.v（含 node 版本发现）**：枚举 brew Cellar node、`~/.local/share/fnm/node-versions/*/installation`、`~/.nvm/versions/node/*`；每个 node 安装是一个 scope（`fnm/v22.12.0` 等）。**fnm 支持不切换 node 直接用不同版本**——这正是 scope 存在的意义：`tsc` 同时存在于 3 个 scope，各自独立 entry。同一 node 版本被两个管理器安装（fnm/nvm 的 v24.3.0）生成两个不同 origin 的 entry，靠 realpath 不同天然不冲突。
- **conda.v**：roots 覆盖 `~/anaconda3`、`~/miniforge3`（+ miniconda3 若存在）及全部 `envs/*`；每个环境一个 scope；enrich 读 `conda-meta/*.json`。
- **brew.v**：`brew --prefix` 实测探测，Intel `/usr/local` 与 M 系 `/opt/homebrew` 双前缀并存则都扫；enrich 调 `brew list --versions` 与 `brew info --json=v2`。
- **app.v**：PATH 目录路径匹配 `*.app/Contents/*` → origin=`app:<Bundle名>`。
- **归因顺序**：registry 顺序即轮询顺序，具体源在前、兜底源（system/manual）在后，首个返回 Attribution 的源胜出。

### TUI 事件循环（手写 ANSI）

```v
term.enable_raw_mode()      // 实现前需实测 term 模块 raw-mode API，备选: termios 直调
loop {
	draw(view_model)        // 全屏重绘（备用屏缓冲区，退格序列恢复）
	key := term.utf8_getchar()
	on_key(key)              // j/k/Tab/[/]/Enter///q → 更新 state → 下一帧
}
```

重绘采用"整屏重画"（工具数据量 < 数千行，性能足够），避免局部 diff 更新的复杂度。

## 4. 并发与错误处理

- **并行扫描**：`spawn` 每根目录一个任务，`ch := chan []Entry` 汇聚。enrich 同法（brew/conda 的子进程调用各一个任务）。
- **deep 探测工作池**：8 个 worker 消费 `chan &Entry`；单命令超时用 spawn+channel 实现（`os.execute` 无超时参数）；执行前 `stdin` 重定向到 `/dev/null`；内置跳过名单。
- **错误分级**：单 entry 失败（无读权限、元数据解析失败）→ 记录到 `Index.warnings`，不中断；`store.save` 失败 → 致命错误退出码 1；`update` 结束时汇总打印 warnings 计数。

## 5. 测试策略

| 模块 | 策略 |
|---|---|
| model | 纯函数单测（过滤/合并/打分），最有价值的目标 |
| source | **fixture 目录树**：测试内用 `os.mkdir_all`+写临时文件构造假 Cellar/假 conda-meta/假 package.json/假 .crates2.json，把各实现的 roots 指向 fixture，断言归因与富化结果——不依赖真机环境；registry 完整性单测（id 唯一、priority 有序） |
| store | 用 `:memory:` 库做 round-trip（save→query 相等）+ 事务原子性 + `user_version` 不匹配时触发重建 |
| report | golden 输出比对 |
| ui | 薄封装，手动验收（键位清单即验收单） |

## 6. 性能预算

- `update`（无 deep）：目标 < 3s（实测本机 ~800 命令 + conda 8 环境）。慢点主要在 brew/conda 子进程，其余是纯目录遍历；SQLite 写入在单事务内完成（< 100ms 量级）。
- 查询命令：< 50ms（SQLite 索引查询 + 内存过滤打分；进程启动占大头）。
- TUI 按键响应：< 16ms/帧。

## 7. 决策记录（ADR 摘要）

| # | 决策 | 理由 | 备选与放弃原因 |
|---|---|---|---|
| 1 | `flag` 而非 `vlib/cli` | 已验证、自动 help 可用 | cli 的 help 实测损坏 |
| 2 | **SQLite 索引**（v2 评审修订，原定 json2 文件） | 用户决策：高速查询与存储；索引化查询、事务原子写、增量更新空间、FTS5 可选 | json2 文件的可 diff 性由 `cmds list --json` 输出替代 |
| 3 | 手写 ANSI TUI | 需求有限、term/ui 残缺 | ncurses 过重 |
| 4 | 自实现模糊匹配 | 生态空白 | 引 fzf 二进制依赖不可接受 |
| 5 | **Source 接口协议**（v2 评审升级，原表驱动 SourceRule） | 用户决策：每源自带发现/归因/富化/子分类/展示，接口多态 + 注册表装载；fnm 不切版本等场景由 npm 源的 scope 直接表达 | 表驱动只能覆盖归因，表达不了 per-source 的 enrich/scopes 差异 |
| 6 | 二级分类（scope）作为一等概念 | 用户决策：conda 环境/node 版本的"激活态可见命令"查询是核心场景；UI、存储（scope 列）、接口（scopes()）三处统一 | 二级信息藏进 origin 字符串无法索引与过滤 |
