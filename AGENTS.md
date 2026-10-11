# cmds — V 命令行工具工作区规范

本仓库用 V 语言开发命令行工具 **cmds**（索引并查询本机已安装命令，按来源分类）。本文件是工作区工程规范；产品需求与架构见 [DESIGN.md](DESIGN.md)。改动数据层（model/discover/enrich/store）前必读 DESIGN.md 对应章节。

## 环境

- 工具链：V 0.5.2（`/usr/local/bin/v`，Homebrew 安装；以 `v version` 输出为准，安装目录名可能滞后）。
- V 经 C 后端编译为原生二进制，产物无运行时依赖。首次编译需预编译工具链，较慢属正常。

## 常用命令

| 任务 | 命令 |
|---|---|
| 运行 | `v run .` |
| 调试构建 | `v .`（产物名默认取目录名，用 `-o cmds` 指定） |
| 发布构建 | `v -prod -o cmds .` |
| 测试（全部 / 聚焦） | `v test .` / `v test internal/util/` |
| 格式化 | `v fmt -w .`（提交前必跑） |
| 静态检查 | `v vet .` |
| 交叉编译 | `v -prod -os linux .`（可换 windows/macos） |
| 添加依赖 | `v install <模块>`（写入 v.mod；克隆后 `v sync` 还原） |

## 目录结构（当前实际）

```
v.mod               # Module { name: 'cmds' ... }
main.v              # 薄入口：全局 flag → 分发子命令（fp.allow_unknown_args() 放行子命令 flag）
cmd/                # 子命令：mod.v 分发、update.v 索引管道、list.v、version.v
internal/model/     # Entry/Occurrence/MergedEntry + 去重/过滤/模糊打分纯函数
internal/scan/      # parse_path/scan_dir/scan_dirs 通用扫描（并行、保序）
internal/source/    # protocol.v 接口 + registry.v + simple/heavy_sources.v 九个实现
internal/store/     # SQLite 索引（open/save_all/load_all/query/meta_get/close）
docs/SPIKE.md       # 各源元数据格式实测记录（改 enrich 前必读）
mockups/            # 交互原型（A2 定稿）
```

模块规则（已在本机 V 0.5.2 实测）：

- 子模块 import 路径 = 相对仓库根的目录路径，**不带** v.mod 模块名前缀：`internal/util` 目录 → `import internal.util`；写 `import cmds.internal.util` 会报 not found。
- 每个目录一个模块，目录内所有 `.v` 文件首行 `module xxx` 必须一致；测试文件与被测代码同模块。
- `v init` 是交互式的，非交互环境直接手写 `Module { name: 'cmds' ... }` 即可被识别。

## 代码规范

- 命名：函数/变量 snake_case，类型/结构体 PascalCase；`pub` 导出，其余模块内私有。
- 格式：一切风格争议以 `v fmt` 输出为准，不手调缩进/空行。
- 字符串不可变；循环拼接用 `strings.Builder`，不要用 `+=`。
- 错误处理：被调函数返回 `!`（Result）或 `?`（Option）；传播时 `!` 只配 Result、`?` 只配 Option，0.5.2 中用 `?` 传播 Result 是编译错误。在 main 边界 `or { eprintln(...); exit(1) }`。panic 只用于程序员 bug，不用于用户输入错误。
- `pub fn` 必须带 `//` 文档注释，`v vet` 对缺失行为 warning，保持零 warning。
- 未用 import 是 warning、未用私有函数是 notice；保持零 warning，确需保留用 `import x as _`。
- 优先用标准库（os、flag、strings、strconv、time、json）；引入第三方前先确认 std 无等价物。
- 平台差异用编译期分支 `$if macos { }` / `$if windows { }`，不用运行时判断；路径拼接用 `os.join_path`。

## CLI 设计规范

- 参数解析一律用 std `flag` 模块；`-h/--help` 和 `--version` 由 flag 自动生成，不要手写。每个 flag 必须带 usage 描述。
- 输出流：数据 → stdout；日志/错误/进度 → stderr（`eprintln`）。
- 退出码：0 成功；1 一般错误；2 用法错误。错误信息格式 `cmds: <原因>`。
- 破坏性操作（删除/覆盖）必须要求显式 `--yes` 或交互确认。

标准入口模板（V 0.5.2 实测可编译）：

```v
module main

import flag
import os

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application('cmds')
	fp.version('0.1.0')
	fp.description('一句话描述工具用途。')
	fp.skip_executable()
	verbose := fp.bool('verbose', `v`, false, 'enable verbose output')
	args := fp.finalize() or {
		eprintln(fp.usage())
		eprintln('error: ${err}')
		exit(1)
	}
	if args.len == 0 {
		eprintln(fp.usage())
		exit(2)
	}
	// 按 args[0] 分发子命令
}
```

## 测试规范

- 测试文件 `*_test.v` 与被测代码同目录，函数名以 `test_` 开头，用 `assert` 断言。
- main.v 只做装配不做逻辑；解析、转换、格式化等纯逻辑放进模块使其可测。

## 文档导航

- [DESIGN.md](DESIGN.md) — 产品需求、来源分类学、数据模型、已确认决策。改数据层前必读。
- [ARCHITECTURE.md](ARCHITECTURE.md) — 模块分层、import 规则、关键机制、技术选型记录（ADR）。
- [PLAN.md](PLAN.md) — 里程碑与任务拆解、验收标准、风险清单。
- [mockups/](mockups/index.html) — 交互原型（浏览器打开）。已定稿：原型 A + 二级 scope tab（a-tabs.html，A2 版本）。
- 依赖政策：**零第三方依赖**（纯标准库，实测结论见 ARCHITECTURE.md §0）。引入任何 vpm 依赖前必须在 ARCHITECTURE.md 登记评估依据。

## 已知坑

- `v test .` 只编译**含有测试文件**的模块——无测试模块的编译错误要到 `v build .` 才暴露；提交前两者都要跑。
- **SQLite（stdlib `db.sqlite`）**：`connect(path)!` 的结果必须声明为 `mut` 才能调用 `close()`（close 是 mut 方法）；写入用 `exec_param_many`（参数化防注入/转义问题），查询用 `exec`/`q_int`/`q_string`，均已实测。`exec` 一次只执行**第一条**语句（多条 DDL 静默丢弃其余）；`get_int` 是 32 位截断，大整数用 `get_string(col).u64()`。
- **V `interface` 动态分发可用**（Source 插件协议的基础）：`[]Source` 异构集合、`?string` Option 返回、`mut []T` 参数的方法签名均实测通过；注意向 interface 数组 push 需 `mut` 声明。
- **os API 实际形态（多处与直觉不符，均已实测）**：`os.execute` 已废弃（告警）→ 用 `os.exec(['cmd','args'])`，返回普通结构体**只有** `exit_code`/`output`（无 stderr，命令不存在时 exit_code=-1）；`os.real_path(p) string`（不是 `realpath`，不失败原样返回）；目录列举是 `os.ls(p) ![]string`（无 `read_dir`）；`os.mkdir_all(p)` 尾参 MkdirParams 可整体省略；`os.stat` 的 `mode` 是 u32（`(mode & 0o170000)==0o100000` 判普通文件、`mode & 0o111` 判执行位）；`os.getenv` 返回普通 string（不能 `if v := os.getenv(...)`）；`os.File.close()` 是 mut 方法；rune 的 `.str()` 返回**十进制数字串**（取字符用 `.ascii_str()`）；`time.unix(t)` 单参数 + `custom_format()`。
- **flag 子命令模式**：全局解析器必须 `fp.allow_unknown_args()`，否则子命令自己的 `--source` 会在主解析器 finalize 时报 unknown flag。
- **`json` 模块已被移除**（V 0.5.x）：必须用 `json2`，API 为 `json2.decode[T](s)` 与 `json2.encode(x, ...)`，已实测可用。
- `vlib/cli`（Commander 式子命令框架）的自动 `--help` 实测报错（README 与实现不符）；子命令框架用 `flag` + 手写分发即可。
- `vlib/term/ui`（termui）组件残缺，TUI 用 `term` 模块手写 ANSI；raw-mode API 用前先做 spike 验证。
- 标准库没有字符串 pad 函数（也无 `string.pad_right` 方法），需要时自行实现（见 cmd/mod.v 的 `pad`）。CJK 字符宽度按 2 列计算，`term.printable_len` 可作参考。
- 标准库没有字符串 pad 函数（也无 `string.pad_right` 方法），需要时自行实现（见 cmd/mod.v 的 `pad`）。
- V 小版本间存在破坏性变更；升级 V 后先跑 `v test .` 全量回归再继续开发。
- flag 的 `bool` 等方法签名含单字符缩写参数（`` `v` ``）与默认值，不要按旧版 `bool_` API 写。
- 交叉编译产物默认落在当前目录，记得用 `-o` 指定并加入清理。
