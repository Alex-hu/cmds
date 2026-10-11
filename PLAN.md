# cmds · 开发计划（v2，按评审意见修订）

评审修订记录（2026-10-11）：交互定原型 A 并增加二级分类 tab；索引存储改 SQLite；架构改为 Source 接口协议；本文已同步。前置设计文档：DESIGN.md / ARCHITECTURE.md / mockups/a-tabs.html（A2 原型）。

## 里程碑总览

| 里程碑 | 内容 | 预估 | 验收方式 |
|---|---|---|---|
| M1 协议与数据层 | Source 接口 + registry + scan + store(SQLite) + update | 4 个工作日 | 本机 `cmds update` 建库，抽样 20 条人工核对 |
| M2 查询命令 | list(--source/--scope)/info/which/search + 表格/JSON | 2 个工作日 | 验收清单逐条过 + 单测全绿 |
| M3 交互 TUI | 原型 A2：一级来源 tab + 二级 scope tab | 3 个工作日 | 键位清单手测 + conda/node 子分类场景演示 |
| M4 deep 探测 | --version 并行探测 + whatis | 1.5 个工作日 | 慢命令超时不挂起、缓存生效 |
| M5 打磨 | dupes/doctor、README、发布构建 | 1.5 个工作日 | `v -prod` 产物 < 5MB、无警告 |

每个里程碑完成的定义：`v fmt -verify` 零输出、`v vet` 零警告、`v test .` 全绿、`v build .` 通过、新增行为有对应测试或验收记录。

## M1 · 协议与数据层（风险最集中，先协议后实现）

任务拆解（按依赖顺序）：

1. `internal/model`：Entry/Attribution/Scope/Occurrence 类型 + merge/filter/scope 过滤纯函数 + 单测。
2. `internal/source/protocol.v` + `registry.v`：接口定义（签名已实测可编译）与注册表；registry 完整性单测（id 唯一、priority 有序）。
3. `internal/scan`：PATH 解析（去重、死目录标记）、并行目录遍历、realpath/stat、可执行位过滤。
4. `internal/store`：SQLite 建库（schema 见 DESIGN.md）、单事务写入、`PRAGMA user_version` 版本管理、`:memory:` round-trip 单测。
5. 各 Source 实现（每个都是独立小闭环：roots→attribute→enrich→scopes）：
   - `system.v`、`manual.v`（最简，先打通管道）；
   - `brew.v`（`brew list --versions` + `brew info --json=v2`，Intel/M 双前缀）；
   - `npm.v`（node 安装发现：brew/fnm/nvm → scope = 版本标识；enrich 读 package.json）；
   - `conda.v`（两套安装 × 全部环境 → scope = 环境名；enrich 读 conda-meta）；
   - `cargo.v`（.crates2.json）、`go.v`（go version -m）、`rvm.v`、`app.v`（*.app bundle 泛化）。
6. `cmd/update`：registry 驱动的管道组装 + 单行进度 + warnings 汇总。

**M1 第半天做技术验证 spike**，逐项实测后固化到 AGENTS.md：
- `brew info --json=v2` 真实字段结构（描述字段名、installed 数组）；
- `.crates2.json` 结构（bin→version 映射）；
- conda-meta JSON 是否含时间戳字段（决定 installed_at 用 mtime 还是元数据）；
- fnm 目录层级（`node-versions/vX/installation/bin`）；
- `go version -m` 在非 Go 二进制上的行为（报错需静默跳过）；
- 系统 libsqlite3 是否启用 FTS5（决定 M2 搜索是否直接上 FTS，未启用则 LIKE+内存打分）。

## M2 · 查询命令

1. `internal/report`：列布局（含 CJK 宽度对齐，占 2 列）、同名合并视图、`--json`。
2. `cmds list --source S --scope E`（scope 对应二级 tab：conda 环境名 / node 版本标识）、`info`、`which`、`search`（SQLite LIKE 粗筛 + 内存 fzf 式打分排序；FTS5 视 spike 结论）。
3. 无索引/过期时的引导提示（"先运行 cmds update"）。
4. golden 测试：固定 fixture 索引 → 固定表格输出。

## M3 · 交互 TUI（原型 A2 已定稿）

1. 终端基础设施 spike：raw mode 开关、备用屏、resize 处理、Ctrl-C 安全退出恢复终端状态（**硬性要求**：任何退出路径都恢复终端，panic hook 也要）。
2. 一级来源 tab（Tab/⇧Tab）+ **二级 scope tab（←/→ 或 h/l）**：scope 列表来自 `source.scopes()`，UI 侧零硬编码；无子分类来源显示占位说明。
3. 表格分页/滚动、`/` 过滤、Enter 详情层（多提供者 + PATH 遮蔽 + scope 归属）。
4. tty 检测：非 tty 时 `cmds` 降级为 help；管道下禁用 ANSI。
5. 验收演示场景：切 Conda→ml 环境只见 jupyter/pip；切 Node→fnm/v22.22.0 只见 tsc 5.8.2/eslint（即"激活某环境/版本时有哪些命令"）。

## M4 · deep 探测

1. 8-worker 池 + 2s 超时（spawn+channel 模式）+ stdin 关闭 + 跳过名单（首版：sudo/ssh/telnet/vi/vim/nano/tmux/screen/less/more/man）。
2. `--version`/`-V`/`version` 三连尝试，首个成功即用；输出取首行并裁剪命令名前缀。
3. whatis 描述补全（`man -k` 数据库）。
4. 结果 UPSERT 回 SQLite，下次 update --deep 跳过已有版本的 entry。

## M5 · 打磨

1. `cmds dupes`（同名多来源清单）与 `cmds doctor`（PATH 重复项/死目录/被遮蔽命令/索引健康度）。
2. README（面向使用者，与 AGENTS.md 分工：AGENTS.md 面向开发）。
3. `v -prod -o cmds .` 发布构建 + 实测冷启动时间；`cmds doctor` 自检通过。

## 风险与缓解

| 风险 | 概率 | 缓解 |
|---|---|---|
| V 版本破坏性变更（0.5.x 内已遇多处） | 高 | 每次开工先跑全量测试；AGENTS.md 记录坑位 |
| `term` raw-mode API 与预期不符 | 中 | M3 前置 spike；最坏情况直接 termios C 调用（V 的 C 互操作成本低） |
| conda 全量索引慢（环境 × 包数量） | 中 | 并行扫 envs；SQLite 按 scope 增量 UPSERT（仅刷新变化的根目录） |
| FTS5 不可用 | 低 | 搜索降级路径已定（LIKE + 内存打分），不阻塞 |
| CJK 对齐细节坑 | 中 | M2 就引入宽度函数并 golden 测试，不留到最后 |
| deep 探测副作用（命令有副作用/挂起） | 中 | 默认不跑；跳过名单 + 超时 + stdin 封闭三重防护 |
