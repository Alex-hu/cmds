// heavy_sources.v — 五个带元数据富化的命令来源实现：
// Homebrew / npm（brew+fnm+nvm 三种 node 安装）/ conda / cargo / go。
// 各源元数据格式与获取方式依据 docs/SPIKE.md 的实测结论。
module source

import internal.model
import json2
import os
import time

// ---------- 公共小工具 ----------

// fmt_ts 把 unix 秒格式化为 'YYYY-MM-DD HH:mm'（Entry.installed_at 约定格式）。
fn fmt_ts(t i64) string {
	return time.unix(t).custom_format('YYYY-MM-DD HH:mm')
}

// under_dir 判断 path 是否严格位于目录 dir 之下（dir + '/' 前缀）。
fn under_dir(path string, dir string) bool {
	return dir != '' && path.starts_with(dir + '/')
}

// cellar_pkg 从 realpath 提取 Homebrew 包名：'/Cellar/<pkg>/<ver>/...' 取 <pkg>；非 Cellar 路径返回空。
fn cellar_pkg(realpath string) string {
	idx := realpath.index('/Cellar/') or { return '' }
	rest := realpath[idx + '/Cellar/'.len..]
	return rest.split('/')[0]
}

// scope_version 从 scope（如 'fnm/v22.12.0'）提取版本号：取末段并去掉前导 'v'；无 '/' 返回空。
fn scope_version(scope string) string {
	if !scope.contains('/') {
		return ''
	}
	ver := scope.all_after_last('/')
	if ver.len > 0 && ver[0] == `v` {
		return ver[1..]
	}
	return ver
}

// ---------- BrewSource：Homebrew ----------

// BrewInfoV2 对应 `brew info --json=v2 --installed` 的顶层结构（formulae 数组）。
struct BrewInfoV2 {
	formulae []BrewFormula
}

// BrewFormula 是 brew info JSON 中单个 formula 的关键字段。
struct BrewFormula {
	name      string
	desc      string
	installed []BrewInstalled
}

// BrewInstalled 是 formula 的已安装版本记录；time 为真实安装时间戳（unix 秒）。
struct BrewInstalled {
	version string
	time    i64
}

// BrewSource 覆盖 Homebrew 安装的命令；Intel（/usr/local）与 Apple Silicon（/opt/homebrew）
// 双前缀并存均支持。scope 无二级分类。
pub struct BrewSource {
pub mut:
	prefixes []string // 全部 Homebrew 前缀
}

// new_brew_source 通过 `brew --prefix` 探测主前缀，并检查互补常见前缀的 Cellar
// 是否存在（双前缀并存场景），构造 BrewSource。
pub fn new_brew_source() BrewSource {
	mut prefixes := []string{}
	mut reported := ''
	res := os.exec(['brew', '--prefix'])
	if res.exit_code == 0 {
		reported = res.output.trim_space()
		if reported != '' {
			prefixes << reported
		}
	}
	// 互补前缀：/opt/homebrew 与 /usr/local 成对检查，Cellar 存在即纳入
	for cand in ['/opt/homebrew', '/usr/local'] {
		if cand == reported || cand in prefixes {
			continue
		}
		if os.is_dir(os.join_path(cand, 'Cellar')) {
			prefixes << cand
		}
	}
	return BrewSource{ prefixes: prefixes }
}

// id 实现 Source 接口：源标识 'brew'。
pub fn (s BrewSource) id() string {
	return 'brew'
}

// label 实现 Source 接口：一级 tab 展示名。
pub fn (s BrewSource) label() string {
	return 'Homebrew'
}

// priority 实现 Source 接口：归因轮询顺序 10。
pub fn (s BrewSource) priority() int {
	return 10
}

// roots 实现 Source 接口：各前缀下的 bin 目录（存在才算）。
pub fn (s BrewSource) roots() []string {
	mut out := []string{cap: s.prefixes.len}
	for p in s.prefixes {
		bin := os.join_path(p, 'bin')
		if os.is_dir(bin) && bin !in out {
			out << bin
		}
	}
	return out
}

// attribute 实现 Source 接口：realpath 位于任一 Cellar 下即归因 brew（无二级 scope）。
pub fn (s BrewSource) attribute(realpath string) ?Attribution {
	if realpath.contains('/Cellar/') {
		return Attribution{ source: 'brew', origin: 'brew', scope: '' }
	}
	return none
}

// scopes 实现 Source 接口：brew 无二级分类，返回空。
pub fn (s BrewSource) scopes() []Scope {
	return []Scope{}
}

// enrich 实现 Source 接口：
//   - `brew list --versions` 建 包名→版本 map，按 realpath 中 Cellar 后第一段取包名填 version；
//   - `brew info --json=v2 --installed`（json2 typed 解码）填 description 与 installed_at
//     （installed[0].time 为真实安装时间，优于 mtime）。
// 任一子命令失败即降级（有版本没描述），绝不返回错误。
pub fn (s BrewSource) enrich(mut entries []model.Entry) ! {
	// 包名 → 版本（brew list --versions 每行 '名 版本'）。
	// 注意：brew 可能因个别 cask 告警以非零码退出但 stdout 完整可用，故只看输出内容。
	mut versions := map[string]string{}
	lres := os.exec(['brew', 'list', '--versions'])
	if lres.output != '' {
		for line in lres.output.split_into_lines() {
			parts := line.split(' ')
			if parts.len >= 2 && parts[0] != '' && !parts[0].contains('(') {
				versions[parts[0]] = parts[1]
			}
		}
	}
	// 包名 → 描述 / 安装时间（brew info --json=v2 --installed；解码失败即降级为空）
	mut descs := map[string]string{}
	mut times := map[string]i64{}
	ires := os.exec(['brew', 'info', '--json=v2', '--installed'])
	if ires.output != '' {
		info := json2.decode[BrewInfoV2](ires.output) or { BrewInfoV2{} }
		for f in info.formulae {
			if f.name == '' {
				continue
			}
			if f.desc != '' {
				descs[f.name] = f.desc
			}
			if f.installed.len > 0 && f.installed[0].time > 0 {
				times[f.name] = f.installed[0].time
			}
		}
	}
	for mut e in entries {
		if e.source != 'brew' {
			continue
		}
		pkg := cellar_pkg(e.realpath)
		if pkg == '' {
			continue
		}
		if pkg in versions {
			e.version = versions[pkg]
		}
		if pkg in descs {
			e.description = descs[pkg]
		}
		if pkg in times {
			e.installed_at = fmt_ts(times[pkg])
		}
	}
}

// ---------- NpmSource：npm（brew / fnm / nvm 三种 node 安装） ----------

// NodeInstall 描述一个独立的 node 安装（brew Cellar、fnm 或 nvm 版本目录）。
pub struct NodeInstall {
pub mut:
	bin_dir       string // <安装根>/bin
	modules_dir   string // <安装根>/lib/node_modules
	origin_prefix string // 发现来源标识：'brew' | 'fnm' | 'nvm'
	scope         string // 二级分类键：'brew'、'fnm/v22.12.0'、'nvm/v24.3.0'
}

// NpmSource 覆盖各 node 安装下的全局 npm 包与 node 本体；scope 为各 node 版本标识。
pub struct NpmSource {
pub mut:
	installs []NodeInstall
}

// make_install 由安装根目录构造 NodeInstall（node 的 bin 与全局 node_modules 布局固定）。
fn make_install(root string, origin_prefix string, scope string) NodeInstall {
	return NodeInstall{
		bin_dir:       os.join_path(root, 'bin')
		modules_dir:   os.join_path(root, 'lib', 'node_modules')
		origin_prefix: origin_prefix
		scope:         scope
	}
}

// new_npm_source 发现本机全部 node 安装：
// (a) brew 前缀 Cellar 下 node 开头的目录（node、node@18 等）；
// (b) ~/.local/share/fnm/node-versions/<ver>/installation；
// (c) ~/.nvm/versions/node/<ver>。
pub fn new_npm_source() NpmSource {
	mut installs := []NodeInstall{}
	// (a) brew Cellar 下的 node 系列
	for prefix in ['/opt/homebrew', '/usr/local'] {
		cellar := os.join_path(prefix, 'Cellar')
		if !os.is_dir(cellar) {
			continue
		}
		for name in os.ls(cellar) or { []string{} } {
			if !name.starts_with('node') {
				continue
			}
			pkg_dir := os.join_path(cellar, name)
			if !os.is_dir(pkg_dir) {
				continue
			}
			for ver in os.ls(pkg_dir) or { []string{} } {
				root := os.join_path(pkg_dir, ver)
				if os.is_dir(root) {
					installs << make_install(root, 'brew', 'brew')
				}
			}
		}
	}
	// (b) fnm
	fnm_root := os.join_path(os.home_dir(), '.local', 'share', 'fnm', 'node-versions')
	if os.is_dir(fnm_root) {
		for d in os.ls(fnm_root) or { []string{} } {
			root := os.join_path(fnm_root, d, 'installation')
			if os.is_dir(root) {
				installs << make_install(root, 'fnm', 'fnm/' + d)
			}
		}
	}
	// (c) nvm
	nvm_root := os.join_path(os.home_dir(), '.nvm', 'versions', 'node')
	if os.is_dir(nvm_root) {
		for d in os.ls(nvm_root) or { []string{} } {
			root := os.join_path(nvm_root, d)
			if os.is_dir(root) {
				installs << make_install(root, 'nvm', 'nvm/' + d)
			}
		}
	}
	// (d) 旧式 npm 全局位置（node 曾以 /usr/local 为 prefix 的遗留安装，bin 在 /usr/local/bin）。
	legacy_modules := os.join_path('/usr/local', 'lib', 'node_modules')
	if os.is_dir(legacy_modules) {
		installs << NodeInstall{
			bin_dir:       '/usr/local/bin'
			modules_dir:   legacy_modules
			origin_prefix: 'legacy'
			scope:         'usr/local'
		}
	}
	return NpmSource{ installs: installs }
}

// id 实现 Source 接口：源标识 'npm'。
pub fn (s NpmSource) id() string {
	return 'npm'
}

// label 实现 Source 接口：一级 tab 展示名。
pub fn (s NpmSource) label() string {
	return 'npm'
}

// priority 实现 Source 接口：归因轮询顺序 5（先于 brew 的泛 /Cellar/ 匹配——
// 否则 brew node 安装下的 npm 全局包会被 brew 抢走归因；npm 的前缀更具体应先轮询）。
pub fn (s NpmSource) priority() int {
	return 5
}

// roots 实现 Source 接口：全部安装的 bin 目录（存在才算）。
pub fn (s NpmSource) roots() []string {
	mut out := []string{}
	for inst in s.installs {
		if inst.bin_dir != '' && os.is_dir(inst.bin_dir) && inst.bin_dir !in out {
			out << inst.bin_dir
		}
	}
	return out
}

// attribute 实现 Source 接口：
//   - 位于某安装的 node_modules 下 → {'npm', 'npm@<scope>', <scope>}；
//   - 位于某安装的 bin 下（且不经 node_modules，即 node 本体）→ {'npm', 'node@<scope>', <scope>}。
//     本体判定限定 node 系二进制名：legacy 安装的 bin_dir 是 /usr/local/bin 这类共享目录，
//     不能把同目录的无关真实文件吞进来。
pub fn (s NpmSource) attribute(realpath string) ?Attribution {
	// 先判包（node_modules），再判 node 本体（bin 且不经 node_modules）
	for inst in s.installs {
		if under_dir(realpath, inst.modules_dir) {
			return Attribution{ source: 'npm', origin: 'npm@' + inst.scope, scope: inst.scope }
		}
	}
	for inst in s.installs {
		if under_dir(realpath, inst.bin_dir) && !realpath.contains('/node_modules/')
			&& is_node_bin(os.base(realpath)) {
			return Attribution{ source: 'npm', origin: 'node@' + inst.scope, scope: inst.scope }
		}
	}
	return none
}

// is_node_bin 判断是否 node 安装自带的核心二进制。
fn is_node_bin(name string) bool {
	return name in ['node', 'npm', 'npx', 'corepack']
}

// scopes 实现 Source 接口：各 node 安装的版本标识（去重、保持发现顺序）。
pub fn (s NpmSource) scopes() []Scope {
	mut out := []Scope{}
	mut seen := map[string]bool{}
	for inst in s.installs {
		if inst.scope == '' || inst.scope in seen {
			continue
		}
		seen[inst.scope] = true
		out << Scope{ id: inst.scope, label: inst.scope }
	}
	return out
}

// PkgJson 是 npm 包 package.json 的关键字段。
struct PkgJson {
	name        string
	version     string
	description string
}

// enrich 实现 Source 接口：
//   - 包类：取 modules_dir 后第一段为包名，读 <modules_dir>/<pkg>/package.json（json2 typed）
//     填 version/description；installed_at 取包目录 mtime；
//   - node 本体类（origin 以 'node@' 开头）：version 取 scope 中的版本号（去 'v'），
//     description 固定为 'Node.js 运行时'。
// 单个 package.json 缺失/损坏只跳过该条，不失败。
pub fn (s NpmSource) enrich(mut entries []model.Entry) ! {
	for mut e in entries {
		if e.source != 'npm' {
			continue
		}
		if e.origin.starts_with('node@') {
			// node 本体
			e.version = scope_version(e.scope)
			e.description = 'Node.js 运行时'
			continue
		}
		// npm 全局包：定位所属安装后读 package.json
		for inst in s.installs {
			if !under_dir(e.realpath, inst.modules_dir) {
				continue
			}
			rest := e.realpath[inst.modules_dir.len + 1..]
			mut pkg := rest.split('/')[0]
			// scoped 包目录形如 '@<scope>/<name>'，包名须取两段
			if pkg.starts_with('@') {
				parts := rest.split('/')
				if parts.len >= 2 && parts[1] != '' {
					pkg = parts[0] + '/' + parts[1]
				}
			}
			if pkg == '' || pkg == '@' {
				break
			}
			pkg_dir := os.join_path(inst.modules_dir, pkg)
			content := os.read_file(os.join_path(pkg_dir, 'package.json')) or { break }
			meta := json2.decode[PkgJson](content) or { break }
			e.version = meta.version
			e.description = meta.description
			if st := os.stat(pkg_dir) {
				e.installed_at = fmt_ts(st.mtime)
			}
			break
		}
	}
}

// ---------- CondaSource：conda / miniforge / anaconda ----------

// CondaEnv 描述一个 conda 环境（base 或 envs/<env>）。
pub struct CondaEnv {
pub mut:
	bin_dir string // 环境 bin 目录绝对路径
	scope   string // 二级分类键：'<安装名>/base'、'<安装名>/envs/<env>'
}

// CondaSource 覆盖 ~/anaconda3、~/miniforge3、~/miniconda3 的 base 与各环境。
pub struct CondaSource {
pub mut:
	envs []CondaEnv
}

// new_conda_source 发现 ~/anaconda3、~/miniforge3、~/miniconda3 中存在者：
// base 环境 + envs/* 各环境。
pub fn new_conda_source() CondaSource {
	mut envs := []CondaEnv{}
	for name in ['anaconda3', 'miniforge3', 'miniconda3'] {
		root := os.join_path(os.home_dir(), name)
		if !os.is_dir(root) {
			continue
		}
		envs << CondaEnv{ bin_dir: os.join_path(root, 'bin'), scope: name + '/base' }
		envs_root := os.join_path(root, 'envs')
		if !os.is_dir(envs_root) {
			continue
		}
		for env in os.ls(envs_root) or { []string{} } {
			bin_dir := os.join_path(envs_root, env, 'bin')
			if os.is_dir(bin_dir) {
				envs << CondaEnv{ bin_dir: bin_dir, scope: name + '/envs/' + env }
			}
		}
	}
	return CondaSource{ envs: envs }
}

// id 实现 Source 接口：源标识 'conda'。
pub fn (s CondaSource) id() string {
	return 'conda'
}

// label 实现 Source 接口：一级 tab 展示名。
pub fn (s CondaSource) label() string {
	return 'conda'
}

// priority 实现 Source 接口：归因轮询顺序 30。
pub fn (s CondaSource) priority() int {
	return 30
}

// roots 实现 Source 接口：全部环境的 bin 目录（存在才算）。
pub fn (s CondaSource) roots() []string {
	mut out := []string{}
	for env in s.envs {
		if env.bin_dir != '' && os.is_dir(env.bin_dir) && env.bin_dir !in out {
			out << env.bin_dir
		}
	}
	return out
}

// attribute 实现 Source 接口：位于某环境 bin 目录下 → {'conda', 'conda:<scope>', <scope>}。
pub fn (s CondaSource) attribute(realpath string) ?Attribution {
	for env in s.envs {
		if under_dir(realpath, env.bin_dir) {
			return Attribution{ source: 'conda', origin: 'conda:' + env.scope, scope: env.scope }
		}
	}
	return none
}

// scopes 实现 Source 接口：全部环境（base + envs/*）。
pub fn (s CondaSource) scopes() []Scope {
	mut out := []Scope{cap: s.envs.len}
	for env in s.envs {
		if env.scope != '' {
			out << Scope{ id: env.scope, label: env.scope }
		}
	}
	return out
}

// CondaMeta 是环境 conda-meta/*.json 的关键字段（files 为该包所装文件的相对路径）。
struct CondaMeta {
	name    string
	version string
	files   []string
}

// CondaPkgInfo 记录某 bin 名对应的包版本及其 meta 文件路径（取 mtime 用）。
struct CondaPkgInfo {
	version   string
	meta_path string
}

// enrich 实现 Source 接口（按环境分组）：扫该环境 conda-meta/*.json（json2 typed），
// 把 files 中的 'bin/<名>' 建 名→(包名,版本) map，entry basename 命中则填 version；
// installed_at 取该 meta 文件 mtime；description 留空（P3 网络补全）。
// meta 目录不存在则跳过该环境。
pub fn (s CondaSource) enrich(mut entries []model.Entry) ! {
	for env in s.envs {
		meta_dir := os.join_path(os.dir(env.bin_dir), 'conda-meta')
		if !os.is_dir(meta_dir) {
			continue
		}
		// bin 名 → (包版本, meta 文件路径)
		mut by_bin := map[string]CondaPkgInfo{}
		for fname in os.ls(meta_dir) or { []string{} } {
			if !fname.ends_with('.json') {
				continue
			}
			meta_path := os.join_path(meta_dir, fname)
			content := os.read_file(meta_path) or { continue }
			meta := json2.decode[CondaMeta](content) or { continue }
			for f in meta.files {
				if f.starts_with('bin/') && !f[4..].contains('/') {
					by_bin[f[4..]] = CondaPkgInfo{ version: meta.version, meta_path: meta_path }
				}
			}
		}
		for mut e in entries {
			if e.source != 'conda' || !under_dir(e.realpath, env.bin_dir) {
				continue
			}
			base := os.file_name(e.realpath)
			if base in by_bin {
				e.version = by_bin[base].version
				if st := os.stat(by_bin[base].meta_path) {
					e.installed_at = fmt_ts(st.mtime)
				}
			}
		}
	}
}

// ---------- CargoSource：cargo install ----------

// Crates2 对应 ~/.cargo/.crates2.json 的顶层结构。
struct Crates2 {
	installs map[string]CratesInstall
}

// CratesInstall 是单个已装 crate 的记录；bins 为它安装的二进制名列表。
struct CratesInstall {
	bins []string
}

// CargoSource 覆盖 `cargo install` 装到 ~/.cargo/bin 的命令。scope 无二级分类。
pub struct CargoSource {
pub mut:
	root         string // ~/.cargo/bin
	crates2_path string // ~/.cargo/.crates2.json（默认；可注入指向 fixture）
}

// new_cargo_source 发现 ~/.cargo/bin，存在则构造 CargoSource。
pub fn new_cargo_source() CargoSource {
	bin := os.join_path(os.home_dir(), '.cargo', 'bin')
	mut s := CargoSource{}
	if os.is_dir(bin) {
		s.root = bin
		s.crates2_path = os.join_path(os.home_dir(), '.cargo', '.crates2.json')
	}
	return s
}

// id 实现 Source 接口：源标识 'cargo'。
pub fn (s CargoSource) id() string {
	return 'cargo'
}

// label 实现 Source 接口：一级 tab 展示名。
pub fn (s CargoSource) label() string {
	return 'cargo'
}

// priority 实现 Source 接口：归因轮询顺序 40。
pub fn (s CargoSource) priority() int {
	return 40
}

// roots 实现 Source 接口：~/.cargo/bin（存在才算）。
pub fn (s CargoSource) roots() []string {
	if s.root != '' && os.is_dir(s.root) {
		return [s.root]
	}
	return []string{}
}

// attribute 实现 Source 接口：位于 ~/.cargo/bin 下 → {'cargo', 'cargo', ''}。
pub fn (s CargoSource) attribute(realpath string) ?Attribution {
	if under_dir(realpath, s.root) {
		return Attribution{ source: 'cargo', origin: 'cargo', scope: '' }
	}
	return none
}

// scopes 实现 Source 接口：cargo 无二级分类，返回空。
pub fn (s CargoSource) scopes() []Scope {
	return []Scope{}
}

// enrich 实现 Source 接口：解析 .crates2.json（json2 typed），key 形如
// '<crate> <version> (registry+...)'，取前两个空格分隔段得 crate+version；
// entry 名 ∈ bins → 填 version；installed_at 取二进制文件 mtime。
// crates2 文件缺失或损坏则整体跳过。
pub fn (s CargoSource) enrich(mut entries []model.Entry) ! {
	if s.root == '' {
		return
	}
	content := os.read_file(s.crates2_path) or { return }
	data := json2.decode[Crates2](content) or { return }
	// 二进制名 → 版本
	mut by_bin := map[string]string{}
	for key, inst in data.installs {
		parts := key.split(' ')
		if parts.len < 2 {
			continue
		}
		for b in inst.bins {
			by_bin[b] = parts[1]
		}
	}
	for mut e in entries {
		if e.source != 'cargo' {
			continue
		}
		if e.name in by_bin {
			e.version = by_bin[e.name]
		}
		if st := os.stat(e.realpath) {
			e.installed_at = fmt_ts(st.mtime)
		}
	}
}

// ---------- GoSource：go install ----------

// GoSource 覆盖 `go install` 装到 $GOPATH/bin 的命令。scope 无二级分类。
pub struct GoSource {
pub mut:
	root string // $GOPATH/bin（默认 ~/go/bin）
}

// new_go_source 发现 GOPATH 环境变量（优先）或 ~/go 下的 bin，存在则构造 GoSource。
pub fn new_go_source() GoSource {
	mut gopath := os.getenv('GOPATH')
	if gopath == '' {
		gopath = os.join_path(os.home_dir(), 'go')
	}
	bin := os.join_path(gopath, 'bin')
	mut s := GoSource{}
	if os.is_dir(bin) {
		s.root = bin
	}
	return s
}

// id 实现 Source 接口：源标识 'go'。
pub fn (s GoSource) id() string {
	return 'go'
}

// label 实现 Source 接口：一级 tab 展示名。
pub fn (s GoSource) label() string {
	return 'Go'
}

// priority 实现 Source 接口：归因轮询顺序 50。
pub fn (s GoSource) priority() int {
	return 50
}

// roots 实现 Source 接口：$GOPATH/bin（存在才算）。
pub fn (s GoSource) roots() []string {
	if s.root != '' && os.is_dir(s.root) {
		return [s.root]
	}
	return []string{}
}

// attribute 实现 Source 接口：位于 $GOPATH/bin 下 → {'go', 'go', ''}。
pub fn (s GoSource) attribute(realpath string) ?Attribution {
	if under_dir(realpath, s.root) {
		return Attribution{ source: 'go', origin: 'go', scope: '' }
	}
	return none
}

// scopes 实现 Source 接口：go 无二级分类，返回空。
pub fn (s GoSource) scopes() []Scope {
	return []Scope{}
}

// enrich 实现 Source 接口：逐 entry 执行 `go version -m <realpath>`（不执行被索引的
// 二进制本身），输出中 'mod\t<module路径>\t<版本>' 行给出 version 与 description；
// 非 Go 二进制（命令失败或无 mod 行）静默跳过；go 命令不存在则整体跳过。
pub fn (s GoSource) enrich(mut entries []model.Entry) ! {
	if s.root == '' {
		return
	}
	// go 不可用（命令不存在）时整体跳过，避免逐条空跑
	probe := os.exec(['go', 'version'])
	if probe.exit_code != 0 {
		return
	}
	for mut e in entries {
		if e.source != 'go' {
			continue
		}
		res := os.exec(['go', 'version', '-m', e.realpath])
		if res.exit_code != 0 {
			continue
		}
		for line in res.output.split_into_lines() {
			l := line.trim_left('\t')
			if !l.starts_with('mod\t') {
				continue
			}
			f := l.split('\t')
			if f.len >= 3 {
				e.version = f[2]
				e.description = f[1]
			}
		}
	}
}
