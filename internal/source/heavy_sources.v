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

// scope_version 从 scope（如 'v22.12.0' 或 'fnm/v22.12.0'）提取版本号：取末段并去掉前导 'v'；无有效数字版本返回空。
fn scope_version(scope string) string {
	ver := if scope.contains('/') { scope.all_after_last('/') } else { scope }
	if ver == 'brew' || ver == 'system' || ver == '' {
		return ''
	}
	if ver.len > 0 && ver[0] == `v` {
		return ver[1..]
	}
	for ch in ver {
		if ch.is_digit() {
			return ver
		}
	}
	return ''
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

// ecosystem 实现 Source 接口：一级生态 'brew'。
pub fn (s BrewSource) ecosystem() string {
	return 'brew'
}

// id 实现 Source 接口：源标识 'brew'。
pub fn (s BrewSource) id() string {
	return 'brew'
}

// label 实现 Source 接口：展示名。
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
		return Attribution{
			source_id: 'brew'
			ecosystem: 'brew'
			manager:   'brew'
			origin:    'brew'
			scope:     ''
		}
	}
	return none
}

// scopes 实现 Source 接口：brew 无三级分类，返回空。
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
		if e.source_id != 'brew' {
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
					installs << make_install(root, 'brew', ver)
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
				installs << make_install(root, 'fnm', d)
			}
		}
	}
	// (c) nvm
	nvm_root := os.join_path(os.home_dir(), '.nvm', 'versions', 'node')
	if os.is_dir(nvm_root) {
		for d in os.ls(nvm_root) or { []string{} } {
			root := os.join_path(nvm_root, d)
			if os.is_dir(root) {
				installs << make_install(root, 'nvm', d)
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
			scope:         'system'
		}
	}
	return NpmSource{ installs: installs }
}

// ecosystem 实现 Source 接口：一级生态 'node'。
pub fn (s NpmSource) ecosystem() string {
	return 'node'
}

// id 实现 Source 接口：源标识 'npm'。
pub fn (s NpmSource) id() string {
	return 'npm'
}

// label 实现 Source 接口：展示名。
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
//   - 位于某安装的 node_modules 下 → {'npm', 'node', <manager>, <scope>, 'npm@<scope>'}；
//   - 位于某安装的 bin 下（且不经 node_modules，即 node 本体）→ {'npm', 'node', <manager>, <scope>, 'node@<scope>'}。
//     本体判定限定 node 系二进制名：legacy 安装的 bin_dir 是 /usr/local/bin 这类共享目录，
//     不能把同目录的无关真实文件吞进来。
pub fn (s NpmSource) attribute(realpath string) ?Attribution {
	// 先判包（node_modules），再判 node 本体（bin 且不经 node_modules）
	for inst in s.installs {
		if under_dir(realpath, inst.modules_dir) {
			orig_scope := if inst.scope.starts_with(inst.origin_prefix + '/') {
				inst.scope
			} else {
				'${inst.origin_prefix}/${inst.scope}'
			}
			return Attribution{
				source_id: 'npm'
				ecosystem: 'node'
				manager:   inst.origin_prefix
				scope:     inst.scope
				origin:    'npm@${orig_scope}'
			}
		}
	}
	for inst in s.installs {
		if under_dir(realpath, inst.bin_dir) && !realpath.contains('/node_modules/')
			&& is_node_bin(os.base(realpath)) {
			orig_scope := if inst.scope.starts_with(inst.origin_prefix + '/') {
				inst.scope
			} else {
				'${inst.origin_prefix}/${inst.scope}'
			}
			return Attribution{
				source_id: 'npm'
				ecosystem: 'node'
				manager:   inst.origin_prefix
				scope:     inst.scope
				origin:    'node@${orig_scope}'
			}
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
		if e.source_id != 'npm' {
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
	manager string // 包管理器名称：'anaconda3'、'miniforge3'、'miniconda3'
	scope   string // 三级环境名：'base'、<env>
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
		envs << CondaEnv{
			bin_dir: os.join_path(root, 'bin')
			manager: name
			scope:   'base'
		}
		envs_root := os.join_path(root, 'envs')
		if !os.is_dir(envs_root) {
			continue
		}
		for env in os.ls(envs_root) or { []string{} } {
			bin_dir := os.join_path(envs_root, env, 'bin')
			if os.is_dir(bin_dir) {
				envs << CondaEnv{
					bin_dir: bin_dir
					manager: name
					scope:   env
				}
			}
		}
	}
	return CondaSource{
		envs: envs
	}
}

// ecosystem 实现 Source 接口：一级生态 'python'。
pub fn (s CondaSource) ecosystem() string {
	return 'python'
}

// id 实现 Source 接口：源标识 'conda'。
pub fn (s CondaSource) id() string {
	return 'conda'
}

// label 实现 Source 接口：展示名。
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

// attribute 实现 Source 接口：位于某环境 bin 目录下 → {'conda', 'python', <manager>, <scope>, '<manager>:<scope>'}。
pub fn (s CondaSource) attribute(realpath string) ?Attribution {
	for env in s.envs {
		if under_dir(realpath, env.bin_dir) {
			return Attribution{
				source_id: 'conda'
				ecosystem: 'python'
				manager:   env.manager
				scope:     env.scope
				origin:    '${env.manager}:${env.scope}'
			}
		}
	}
	return none
}

// scopes 实现 Source 接口：全部环境（去重后）。
pub fn (s CondaSource) scopes() []Scope {
	mut out := []Scope{cap: s.envs.len}
	mut seen := map[string]bool{}
	for env in s.envs {
		if env.scope != '' && !seen[env.scope] {
			seen[env.scope] = true
			out << Scope{
				id:    env.scope
				label: env.scope
			}
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
					by_bin[f[4..]] = CondaPkgInfo{
						version:   meta.version
						meta_path: meta_path
					}
				}
			}
		}
		for mut e in entries {
			if e.source_id != 'conda' || !under_dir(e.realpath, env.bin_dir) {
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

// ---------- UvSource：Python uv 包管理器 ----------

// UvSource 负责发现 ~/.local/share/uv 中的工具与 Python 解释器。
pub struct UvSource {
pub mut:
	tools_dir  string
	python_dir string
	local_bin  string
}

// new_uv_source 初始化 UvSource。
pub fn new_uv_source() UvSource {
	home := os.home_dir()
	return UvSource{
		tools_dir:  os.join_path(home, '.local', 'share', 'uv', 'tools')
		python_dir: os.join_path(home, '.local', 'share', 'uv', 'python')
		local_bin:  os.join_path(home, '.local', 'bin')
	}
}

// ecosystem 实现 Source 接口：一级生态 'python'。
pub fn (s UvSource) ecosystem() string {
	return 'python'
}

// id 实现 Source 接口：源标识 'uv'。
pub fn (s UvSource) id() string {
	return 'uv'
}

// label 实现 Source 接口：展示名。
pub fn (s UvSource) label() string {
	return 'uv'
}

// priority 实现 Source 接口：归因轮询顺序 25（优先于 conda 与 manual）。
pub fn (s UvSource) priority() int {
	return 25
}

// roots 实现 Source 接口：uv 工具入口位于 ~/.local/bin，已由 manual/PATH 统一扫描，此处返回空防重复。
pub fn (s UvSource) roots() []string {
	return []string{}
}

// attribute 实现 Source 接口：realpath 位于 uv tools/python 或 uv/uvx 二进制。
pub fn (s UvSource) attribute(realpath string) ?Attribution {
	if s.tools_dir != '' && under_dir(realpath, s.tools_dir) {
		rel := realpath.all_after(s.tools_dir).trim_left(os.path_separator)
		tool_name := rel.all_before(os.path_separator)
		return Attribution{
			source_id: 'uv'
			ecosystem: 'python'
			manager:   'uv'
			scope:     'tools'
			origin:    'uv:tool/' + tool_name
		}
	}
	if s.python_dir != '' && under_dir(realpath, s.python_dir) {
		return Attribution{
			source_id: 'uv'
			ecosystem: 'python'
			manager:   'uv'
			scope:     'toolchain'
			origin:    'uv:python'
		}
	}
	base := os.file_name(realpath)
	if base in ['uv', 'uvx'] && under_dir(realpath, s.local_bin) {
		return Attribution{
			source_id: 'uv'
			ecosystem: 'python'
			manager:   'uv'
			scope:     'tools'
			origin:    'uv:self'
		}
	}
	return none
}

// scopes 实现 Source 接口：uv 提供 tools 与 toolchain。
pub fn (s UvSource) scopes() []Scope {
	return [
		Scope{
			id:    'tools'
			label: '工具'
		},
		Scope{
			id:    'toolchain'
			label: '工具链'
		},
	]
}

// enrich 实现 Source 接口：通过 `uv tool list` 与 `uv --version` 富化版本信息。
pub fn (s UvSource) enrich(mut entries []model.Entry) ! {
	mut versions := map[string]string{}
	res := os.exec(['uv', 'tool', 'list'])
	if res.exit_code == 0 && res.output != '' {
		mut cur_ver := ''
		for line in res.output.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed.starts_with('- ') {
				bin_name := trimmed[2..].trim_space()
				if cur_ver != '' {
					versions[bin_name] = cur_ver
				}
			} else if trimmed.contains(' v') {
				parts := trimmed.split(' ')
				for p in parts {
					if p.starts_with('v') && p.len > 1 {
						cur_ver = p[1..]
						break
					}
				}
			}
		}
	}

	// uv 自驱版本
	uv_res := os.exec(['uv', '--version'])
	if uv_res.exit_code == 0 && uv_res.output != '' {
		parts := uv_res.output.trim_space().split(' ')
		if parts.len >= 2 {
			versions['uv'] = parts[1]
			versions['uvx'] = parts[1]
		}
	}

	for mut e in entries {
		if e.source_id != 'uv' {
			continue
		}
		if v := versions[e.name] {
			e.version = v
		}
		if st := os.stat(e.realpath) {
			e.installed_at = fmt_ts(st.mtime)
		}
		if e.name == 'uv' {
			e.description = 'Extremely fast Python package installer and resolver'
		} else if e.name == 'uvx' {
			e.description = 'Execute tools from Python packages in ephemeral environments'
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

// ecosystem 实现 Source 接口：一级生态 'rust'。
pub fn (s CargoSource) ecosystem() string {
	return 'rust'
}

// id 实现 Source 接口：源标识 'cargo'。
pub fn (s CargoSource) id() string {
	return 'cargo'
}

// label 实现 Source 接口：展示名。
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

// attribute 实现 Source 接口：位于 ~/.cargo/bin 下 → {'cargo', 'rust', 'cargo', '', 'cargo'}。
pub fn (s CargoSource) attribute(realpath string) ?Attribution {
	if under_dir(realpath, s.root) {
		return Attribution{
			source_id: 'cargo'
			ecosystem: 'rust'
			manager:   'cargo'
			origin:    'cargo'
			scope:     ''
		}
	}
	return none
}

// scopes 实现 Source 接口：cargo 无三级分类，返回空。
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
		if e.source_id != 'cargo' {
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

// ---------- GoSource：go install 与 Go 工具链 ----------

// GoSource 覆盖 `go install` 装到 $GOPATH/bin、$GOBIN 的命令以及 $GOROOT/bin（/usr/local/go/bin 等）工具链命令。scope 无二级分类。
pub struct GoSource {
pub mut:
	roots []string // $GOBIN, $GOPATH/bin, $GOROOT/bin
}

// new_go_source 发现 Go 的可执行目录（$GOBIN, $GOPATH/bin, $GOROOT/bin 及标准安装目录）。
pub fn new_go_source() GoSource {
	mut roots := []string{}

	// 1. $GOBIN
	gobin := os.getenv('GOBIN')
	if gobin != '' && os.is_dir(gobin) && gobin !in roots {
		roots << gobin
	}

	// 2. $GOPATH/bin（若无 GOPATH 环境变量则探测 ~/go/bin）
	mut gopath := os.getenv('GOPATH')
	if gopath == '' {
		gopath = os.join_path(os.home_dir(), 'go')
	}
	for p in gopath.split(':') {
		if p != '' {
			bin := os.join_path(p, 'bin')
			if os.is_dir(bin) && bin !in roots {
				roots << bin
			}
		}
	}

	// 3. $GOROOT/bin
	goroot := os.getenv('GOROOT')
	if goroot != '' {
		bin := os.join_path(goroot, 'bin')
		if os.is_dir(bin) && bin !in roots {
			roots << bin
		}
	}

	// 4. 标准 macOS / Linux 安装路径
	for cand in ['/usr/local/go', '/opt/homebrew/opt/go/libexec', '/usr/lib/go'] {
		bin := os.join_path(cand, 'bin')
		if os.is_dir(bin) && bin !in roots {
			roots << bin
		}
	}

	// 5. 若系统已有 go 命令，通过 go env 动态补齐 GOROOT 与 GOPATH
	probe_root := os.exec(['go', 'env', 'GOROOT'])
	if probe_root.exit_code == 0 {
		g_root := probe_root.output.trim_space()
		if g_root != '' {
			bin := os.join_path(g_root, 'bin')
			if os.is_dir(bin) && bin !in roots {
				roots << bin
			}
		}
	}
	probe_path := os.exec(['go', 'env', 'GOPATH'])
	if probe_path.exit_code == 0 {
		g_path := probe_path.output.trim_space()
		if g_path != '' {
			for p in g_path.split(':') {
				bin := os.join_path(p, 'bin')
				if os.is_dir(bin) && bin !in roots {
					roots << bin
				}
			}
		}
	}

	return GoSource{
		roots: roots
	}
}

// ecosystem 实现 Source 接口：一级生态 'go'。
pub fn (s GoSource) ecosystem() string {
	return 'go'
}

// id 实现 Source 接口：源标识 'go'。
pub fn (s GoSource) id() string {
	return 'go'
}

// label 实现 Source 接口：展示名。
pub fn (s GoSource) label() string {
	return 'Go'
}

// priority 实现 Source 接口：归因轮询顺序 50。
pub fn (s GoSource) priority() int {
	return 50
}

// roots 实现 Source 接口：全部 Go bin 目录（存在才算）。
pub fn (s GoSource) roots() []string {
	mut out := []string{}
	for r in s.roots {
		if r != '' && os.is_dir(r) && r !in out {
			out << r
		}
	}
	return out
}

// attribute 实现 Source 接口：位于任一 Go bin 目录下 → {'go', 'go', 'go', <scope>, 'go:<scope>'}。
pub fn (s GoSource) attribute(realpath string) ?Attribution {
	for r in s.roots {
		if under_dir(realpath, r) {
			is_toolchain := os.file_name(realpath) in ['go', 'gofmt'] || r.contains('/go/bin') || r.contains('libexec/bin')
			scope_name := if is_toolchain { 'toolchain' } else { 'gopath' }
			return Attribution{
				source_id: 'go'
				ecosystem: 'go'
				manager:   'go'
				origin:    'go:' + scope_name
				scope:     scope_name
			}
		}
	}
	return none
}

// scopes 实现 Source 接口：go 的三级分类（标准工具链 vs GOPATH）。
pub fn (s GoSource) scopes() []Scope {
	return [
		Scope{ id: 'toolchain', label: '标准工具链' },
		Scope{ id: 'gopath', label: 'GOPATH' },
	]
}

// enrich 实现 Source 接口：逐 entry 执行 `go version -m <realpath>`（不执行被索引的
// 二进制本身），输出中：
// 1. 标准 Go 工具链二进制（如 go, gofmt）：首行含 ': go<version>'，'path\tcmd/<tool>'；
// 2. go install 模块：'mod\t<module路径>\t<版本>'；
// 非 Go 二进制（命令失败或无匹配行）静默跳过；go 命令不存在则整体跳过。
pub fn (s GoSource) enrich(mut entries []model.Entry) ! {
	if s.roots.len == 0 {
		return
	}
	// go 不可用（命令不存在）时整体跳过，避免逐条空跑
	probe := os.exec(['go', 'version'])
	if probe.exit_code != 0 {
		return
	}
	for mut e in entries {
		if e.source_id != 'go' {
			continue
		}
		res := os.exec(['go', 'version', '-m', e.realpath])
		if res.exit_code != 0 {
			continue
		}
		lines := res.output.split_into_lines()
		if lines.len == 0 {
			continue
		}
		first_line := lines[0]
		if first_line.contains(': go') {
			parts := first_line.split(': go')
			if parts.len >= 2 {
				e.version = parts[1].trim_space()
			}
		}
		for line in lines {
			l := line.trim_left('\t')
			if l.starts_with('mod\t') {
				f := l.split('\t')
				if f.len >= 3 {
					e.version = f[2]
					e.description = f[1]
				}
			} else if l.starts_with('path\t') {
				f := l.split('\t')
				if f.len >= 2 && e.description == '' {
					if e.name == 'go' {
						e.description = 'Go toolchain binary'
					} else if e.name == 'gofmt' {
						e.description = 'Go code formatter'
					} else {
						e.description = f[1]
					}
				}
			}
		}
	}
}

// ---------- PnpmSource：pnpm 全局安装 ----------

// PnpmPkgJson 是 pnpm 包 package.json 的关键字段。
struct PnpmPkgJson {
	name        string
	version     string
	description string
	bin         json2.Any
}

// PkgMetadata 保存二进制包的提取版本与描述。
struct PkgMetadata {
	version     string
	description string
}

// parse_pnpm_pkg_json 解析 pnpm 的 package.json 并提取 bin 映射。
fn parse_pnpm_pkg_json(path string, mut m map[string]PkgMetadata) {
	if !os.is_file(path) {
		return
	}
	content := os.read_file(path) or { return }
	pkg := json2.decode[PnpmPkgJson](content) or { return }
	if pkg.name == '' {
		return
	}
	def_name := pkg.name.all_after_last('/')
	meta := PkgMetadata{
		version:     pkg.version
		description: pkg.description
	}
	m[def_name] = meta
	match pkg.bin {
		string {
			m[def_name] = meta
		}
		map[string]json2.Any {
			for k, _ in pkg.bin {
				m[k] = meta
			}
		}
		else {}
	}
}

// PnpmSource 覆盖 `pnpm add -g` 安装到 $PNPM_HOME（默认 macOS 为 ~/Library/pnpm）的命令。scope 无二级分类。
pub struct PnpmSource {
pub mut:
	root       string // $PNPM_HOME（例如 ~/Library/pnpm）
	global_dir string // $PNPM_HOME/global
}

// new_pnpm_source 发现 PNPM_HOME 环境变量（优先）或平台默认路径，存在则构造 PnpmSource。
pub fn new_pnpm_source() PnpmSource {
	mut pnpm_home := os.getenv('PNPM_HOME')
	if pnpm_home == '' {
		$if macos {
			pnpm_home = os.join_path(os.home_dir(), 'Library', 'pnpm')
		} $else {
			pnpm_home = os.join_path(os.home_dir(), '.local', 'share', 'pnpm')
		}
	}
	mut s := PnpmSource{}
	if os.is_dir(pnpm_home) {
		s.root = pnpm_home
		global_path := os.join_path(pnpm_home, 'global')
		if os.is_dir(global_path) {
			s.global_dir = global_path
		}
	}
	return s
}

// ecosystem 实现 Source 接口：一级生态 'node'。
pub fn (s PnpmSource) ecosystem() string {
	return 'node'
}

// id 实现 Source 接口：源标识 'pnpm'。
pub fn (s PnpmSource) id() string {
	return 'pnpm'
}

// label 实现 Source 接口：展示名。
pub fn (s PnpmSource) label() string {
	return 'pnpm'
}

// priority 实现 Source 接口：归因轮询顺序 7（位于 npm(5) 之后，brew(10) 之前）。
pub fn (s PnpmSource) priority() int {
	return 7
}

// roots 实现 Source 接口：$PNPM_HOME（存在才算）。
pub fn (s PnpmSource) roots() []string {
	if s.root != '' && os.is_dir(s.root) {
		return [s.root]
	}
	return []string{}
}

// attribute 实现 Source 接口：位于 $PNPM_HOME 目录下 → {'pnpm', 'node', 'pnpm', '', 'pnpm:global'}。
pub fn (s PnpmSource) attribute(realpath string) ?Attribution {
	if under_dir(realpath, s.root) {
		return Attribution{
			source_id: 'pnpm'
			ecosystem: 'node'
			manager:   'pnpm'
			origin:    'pnpm:global'
			scope:     ''
		}
	}
	return none
}

// scopes 实现 Source 接口：pnpm 全局无三级分类，返回空。
pub fn (s PnpmSource) scopes() []Scope {
	return []Scope{}
}

// enrich 实现 Source 接口：从 global/*/node_modules 读取各包的 package.json 元数据，
// 或从包装脚本解析关联的包版本与描述。
pub fn (s PnpmSource) enrich(mut entries []model.Entry) ! {
	if s.root == '' {
		return
	}
	mut bin_map := map[string]PkgMetadata{}
	if s.global_dir != '' && os.is_dir(s.global_dir) {
		for ver_dir in os.ls(s.global_dir) or { []string{} } {
			nm_dir := os.join_path(s.global_dir, ver_dir, 'node_modules')
			if !os.is_dir(nm_dir) {
				continue
			}
			for entry in os.ls(nm_dir) or { []string{} } {
				if entry.starts_with('.') {
					continue
				}
				if entry.starts_with('@') {
					scope_dir := os.join_path(nm_dir, entry)
					for sub_entry in os.ls(scope_dir) or { []string{} } {
						pkg_path := os.join_path(scope_dir, sub_entry, 'package.json')
						parse_pnpm_pkg_json(pkg_path, mut bin_map)
					}
				} else {
					pkg_path := os.join_path(nm_dir, entry, 'package.json')
					parse_pnpm_pkg_json(pkg_path, mut bin_map)
				}
			}
		}
	}

	for mut e in entries {
		if e.source_id != 'pnpm' {
			continue
		}
		if st := os.stat(e.realpath) {
			e.installed_at = fmt_ts(st.mtime)
		}
		if e.name in bin_map {
			info := bin_map[e.name]
			if info.version != '' {
				e.version = info.version
			}
			if info.description != '' {
				e.description = info.description
			}
		} else {
			// 从包装脚本内容探测版本与包名
			content := os.read_file(e.realpath) or { '' }
			if idx := content.index('.pnpm/') {
				rest := content[idx + 6..]
				if slash_idx := rest.index('/') {
					pkg_spec := rest[..slash_idx]
					if at_idx := pkg_spec.last_index('@') {
						if at_idx > 0 {
							e.version = pkg_spec[at_idx + 1..]
							e.description = pkg_spec[..at_idx].replace('+', '/')
						}
					}
				}
			}
		}
	}
}
