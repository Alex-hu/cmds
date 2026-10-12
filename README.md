# cmds — 本机命令行工具索引与查询

扫描这台 Mac 上所有已安装的 CLI 命令，按**来源**归类——系统命令、Homebrew、各版本 Node 下的 npm 全局包、各 conda 环境的命令、cargo / go 安装的工具、应用内嵌命令——并给出版本、功能描述、安装位置、安装时间。本地 SQLite 索引，查询毫秒级。

## 它解决什么问题

- 机器上有 brew / fnm / nvm 多套 node：`tsc`、`claude` 在每个版本下各装了一份，都是什么版本？当前生效的是哪个？
- conda 好几个环境：`jupyter` 装在哪个环境里？
- `/usr/local/bin` 里这个命令是谁装的、什么版本、什么时候装的、被 PATH 里更靠前的同名命令遮蔽了吗？

## 快速开始

需要 [V 语言](https://vlang.io) 0.5.x：

```sh
v -prod -o cmds .
./cmds update     # 建立索引（样例机器：3417 条命令，约 6 秒）
./cmds list --source brew
```

开发模式：`v run . update`。

## 使用

```
Usage: cmds [options] <command> [args]

Commands:
  update [--deep]                  重建索引（deep 探测见路线图）
  list [--source S] [--scope E]    列出已索引命令
  version                          打印版本信息。
  help                             显示帮助。

先运行 cmds update 建立索引。
```

全局选项：`-v, --verbose` 显示各源扫描/富化统计；`-h/--help`、`--version` 自动生成。

按二级分类过滤（回答"激活该环境 / 该 node 版本时有哪些命令"）：

```sh
cmds list --source npm --scope nvm/v24.3.0      # 该 node 版本下的全局包
cmds list --source conda --scope miniforge3/envs/py313
```

真实输出示例（节选）：

```
$ cmds --verbose update
扫描 23 个目录，3422 个文件
去重后 3417 条
npm: 32 条已富化
brew: 954 条已富化
conda: 1030 条已富化
...
已索引 3417 条命令 → ~/Library/Caches/cmds/index.db（6178ms，warnings=0）

$ cmds list --source npm
NAME        SOURCE  SCOPE          VERSION  INSTALLED           PATH
claude      npm     fnm/v24.3.0    2.1.150  2026-05-23 08:01    ~/.local/share/fnm/.../claude-code/bin/claude.exe
claude      npm     nvm/v24.3.0    2.0.42   2025-11-16 15:35    ~/.nvm/versions/node/v24.3.0/.../cli.js
tsc         npm     usr/local      5.0.2    ...                 /usr/local/lib/node_modules/typescript/bin/tsc
```

索引缓存：`~/Library/Caches/cmds/index.db`（SQLite，可用环境变量 `CMDS_CACHE_DIR` 覆盖目录）。查询命令只读缓存，重建索引用 `cmds update`。

## 来源分类

| source | 覆盖内容 | origin / scope 示例 |
|---|---|---|
| `system` | /bin、/usr/bin、/sbin、/usr/sbin | `system` |
| `brew` | Homebrew（Intel `/usr/local` 与 M 系列 `/opt/homebrew` 双前缀，并存都扫） | `brew`，版本取自 Cellar 路径与 brew 元数据 |
| `npm` | 每个 node 安装（brew Cellar / fnm / nvm / 旧式 /usr/local）下的全局包与 node 本体 | scope：`brew`、`fnm/v22.12.0`、`nvm/v24.3.0`、`usr/local` |
| `conda` | 每套安装（anaconda3 / miniforge3 / miniconda3）的 base 与全部 `envs/*` | scope：`miniforge3/base`、`miniforge3/envs/ml` |
| `cargo` | `~/.cargo/bin`（rustup shim 自动识别并跳过） | `cargo` |
| `go` | `$GOPATH/bin`，`go version -m` 读二进制内嵌构建信息 | `go` |
| `rvm` | `~/.rvm/bin` | `rvm` |
| `app` | PATH 中位于 `*.app` bundle 内的目录（如 ZCode 内嵌的 rg） | `app:ZCode` |
| `manual` | PATH 中无法归因到以上来源的目录（兜底） | `manual` |

新增一种来源只需实现 `Source` 接口并注册，核心管道与 UI 零改动（见 [ARCHITECTURE.md](ARCHITECTURE.md)）。

## 数据字段

每条命令记录：名称、来源（source/origin/scope）、真实路径（符号链接已解析）、在 PATH 中的每次出现（用于同名遮蔽分析）、版本、描述、安装时间、文件大小、类型（binary/script）。

安装时间为近似值（文件/包目录 mtime），例外：brew 用其元数据中的真实安装时间戳。

## 安全性

- 索引过程**只读文件系统元数据与各包管理器自己的注册信息**（package.json、conda-meta、.crates2.json、`go version -m`），不执行任何被索引的命令。
- 全部数据留在本机，无网络请求。

## 平台

仅支持 macOS，Intel 与 Apple Silicon 均可（Homebrew 双前缀自动探测）。

## 路线图

- **M2**：`cmds info <name>`（多提供者 + 遮蔽关系）、`cmds which <name>`、`cmds search`、`--json` 输出、CJK 对齐表格
- **M3**：交互式 TUI——一级来源 tab + 二级环境/node 版本 tab（原型见 [mockups/](mockups/index.html)）
- **M4**：`update --deep`（并行 `--version` 探测补全系统命令版本，带超时与跳过名单）、whatis 描述
- **M5**：`cmds dupes`（同名冲突清单）、`cmds doctor`（PATH 重复项/死目录/遮蔽诊断）

## 开发

```sh
v test .      # 36 个测试
v build .
v fmt -w . && v vet .
```

文档分工：[DESIGN.md](DESIGN.md) 产品需求 · [ARCHITECTURE.md](ARCHITECTURE.md) 代码架构 · [PLAN.md](PLAN.md) 开发计划 · [AGENTS.md](AGENTS.md) 工程规范 · [docs/SPIKE.md](docs/SPIKE.md) 各源元数据格式实测记录。

License: MIT
