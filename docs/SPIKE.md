# M1 Spike 实测记录（2026-10-11，本机 macOS / V 0.5.2）

各 Source 富化实现的数据依据，全部实测：

## 1. Homebrew

- `brew --prefix` → 前缀（本机 `/usr/local`，Intel；M 系 `/opt/homebrew`）。
- `brew list --versions` → 每行 `名 版本`（如 `abseil 20260817.0`），批量拿版本，快。
- `brew info --json=v2 --installed` → `formulae[]`，关键字段：
  - `name` / `full_name`、`desc`（英文描述）、`versions.stable`；
  - `installed[]`：`version`、**`time`（unix 秒，真实安装时间戳）**、`installed_on_request`。
  - 注意：installed_at 用 `installed[0].time`（优于 mtime）；desc 用 `desc`。
- 归因：realpath 含 `/Cellar/<pkg>/<ver>/`，pkg 名取 Cellar 后第一段。

## 2. cargo（~/.cargo/.crates2.json）

结构：`{"installs": {"<crate> <version> (registry+…)": {"bins": ["bin名"], …}}}`。
bin→版本映射：遍历 installs，key 按空格切前两段得 crate+version，value.bins 里是它安装的二进制名。

## 3. conda（envs/<env>/conda-meta/*.json）

- 字段：`name`、`version`、`build`、`files[]`（该包装的文件相对路径，如 `bin/sqlite3`）、`channel`；**无时间字段** → installed_at 用该 json 文件的 mtime。
- bin→包归因：扫某环境全部 meta 的 `files[]` 中 `bin/<name>` 项，建 map 后反查 entry 的 basename。
- 环境发现：`~/miniforge3/envs/`（本机还有 `~/anaconda3`；环境如 `py313`）。scope = `<安装名>/envs/<env>` 与 `<安装名>/base`。
- 描述：本地无来源（留空，P3 网络补全）。

## 4. fnm / nvm node 安装层级

- fnm：`~/.local/share/fnm/node-versions/v22.12.0/installation/bin/{node,npm,npx,corepack}` ✓
- nvm：`~/.nvm/versions/node/v24.3.0/bin/…`
- npm 全局包：`<installation>/lib/node_modules/<pkg>/…`，包元数据在 `<pkg>/package.json`（name/version/description）。

## 5. go（`go version -m <二进制>`）

- 首行 `<path>: go1.14.2`；`mod\t<module路径>\t<v版本>\t<h1:…>` 行给出 module 与版本（如 dlv → `v1.7.1`）。
- 非 Go 二进制：命令失败/无 mod 行 → 静默跳过，version 留空。
- **不执行被索引的二进制本身**，安全。

## 6. SQLite

- 系统 libsqlite3 **已启用 FTS5**（`pragma compile_options` 确认）→ M2 搜索可用 FTS5（LIKE+内存打分作后备）。
- V 侧实测：`db.sqlite` connect/DDL/`exec_param_many`/`exec`/`q_int` 全通；`connect` 结果需 `mut` 才能调 `close()`。

## 7. V 语言结论

- interface 方法可带 `mut []T` 参数（实测）→ `enrich(mut entries []model.Entry) !` 签名成立。
- `[]Source` 动态分发、`?T` 返回方法实测可用。
- Entry.scope 用普通 `string`（空串=无二级分类），避免 Option 结构体字段的兼容风险。
