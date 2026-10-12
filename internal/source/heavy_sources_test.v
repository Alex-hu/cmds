// heavy_sources_test.v — 五源实现的 fixture 测试（不依赖真机brew/conda 等真实安装）。
// brew/conda 的 enrich 依赖 subprocess 输出，无法用 fixture 覆盖，只测纯逻辑部分；
// attribute / scopes / roots / 注入路径的 enrich 全覆盖。
module source

import internal.model
import os
import time

// mkfake_exec 在 path 创建可执行的假二进制（shell 桥接脚本）。
fn mkfake_exec(path string) {
	os.mkdir_all(os.dir(path)) or { panic(err) }
	os.write_file(path, '#!/bin/sh\nexit 0\n') or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
}

// mkfile 写文本文件（自动创建父目录）。
fn mkfile(path string, content string) {
	os.mkdir_all(os.dir(path)) or { panic(err) }
	os.write_file(path, content) or { panic(err) }
}

// fixture_root 为每个测试创建独立的临时目录。
// 用 os.real_path 解析过的临时目录作基底，避免 macOS /tmp→/private/tmp 符号链接
// 导致 fixture 内 real_path 结果与构造路径前缀不匹配。
fn fixture_root(name string) string {
	base := os.real_path(os.temp_dir())
	p := os.join_path(base, 'cmds-heavy-${name}-${time.now().unix_milli()}')
	os.mkdir_all(p) or { panic(err) }
	return p
}

// assert_none_attr 断言归因结果为 none（不属于该源）。
fn assert_none_attr(a ?Attribution) {
	if a != none {
		assert false
	}
}

// test_helpers 覆盖内部小工具函数。
fn test_helpers() {
	assert cellar_pkg('/usr/local/Cellar/git/2.47.1/bin/git') == 'git'
	assert cellar_pkg('/opt/homebrew/Cellar/node@18/18.20.4/bin/node') == 'node@18'
	assert cellar_pkg('/usr/local/Cellar/git') == 'git'
	assert cellar_pkg('/usr/local/bin/git') == ''
	assert scope_version('fnm/v22.12.0') == '22.12.0'
	assert scope_version('nvm/v24.3.0') == '24.3.0'
	assert scope_version('brew') == ''
	assert under_dir('/a/b/c', '/a/b') == true
	assert under_dir('/a/binx', '/a/bin') == false
	assert under_dir('/a/bin', '/a/bin') == false // 恰为目录本身不算其下
	s := fmt_ts(1728600000)
	assert s.len == 16
	assert s[4] == `-` && s[7] == `-` && s[10] == ` ` && s[13] == `:`
}

// test_interface_conformance 六源实现 Source 接口：id/label/priority 全部符合约定。
fn test_interface_conformance() {
	mut sources := []Source{cap: 6}
	sources << BrewSource{}
	sources << NpmSource{}
	sources << PnpmSource{}
	sources << CondaSource{}
	sources << CargoSource{}
	sources << GoSource{}
	assert sources.len == 6
	assert sources.map(it.id()) == ['brew', 'npm', 'pnpm', 'conda', 'cargo', 'go']
	assert sources.map(it.priority()) == [10, 5, 7, 30, 40, 50]
	assert sources.map(it.label()) == ['Homebrew', 'npm', 'pnpm', 'conda', 'cargo', 'Go']
	// 经接口调用 enrich（空列表）不应报错
	mut es := []model.Entry{}
	for src in sources {
		src.enrich(mut es) or { assert false }
	}
}

// test_brew_attribute_roots_scopes 假 Cellar fixture：归因/roots/scopes。
fn test_brew_attribute_roots_scopes() {
	root := fixture_root('brew')
	prefix := os.join_path(root, 'prefix')
	mkfake_exec(os.join_path(prefix, 'Cellar', 'git', '2.47.1', 'bin', 'git'))
	os.mkdir_all(os.join_path(prefix, 'bin')) or { panic(err) }
	src := BrewSource{ prefixes: [prefix] }
	assert src.id() == 'brew'
	assert src.priority() == 10
	assert src.roots() == [os.join_path(prefix, 'bin')]
	assert src.scopes() == []
	gitpath := os.join_path(prefix, 'Cellar', 'git', '2.47.1', 'bin', 'git')
	attr := src.attribute(gitpath) or {
		assert false
		return
	}
	assert attr.source_id == 'brew'
	assert attr.ecosystem == 'brew'
	assert attr.manager == 'brew'
	assert attr.origin == 'brew'
	assert attr.scope == ''
	assert_none_attr(src.attribute('/usr/bin/ls'))
	assert_none_attr(src.attribute(os.join_path(root, 'other', 'bin', 'x')))
}

// test_brew_cellar_prefix_out_of_scope 无前缀注入时 brew 对非 Cellar 路径一律 none。
fn test_brew_empty_prefixes() {
	src := BrewSource{}
	assert src.roots() == []
	assert_none_attr(src.attribute('/opt/homebrew/bin/node'))
	// /Cellar/ 判定与前缀注入无关：只要路径形态匹配即归因（由扫描 roots 决定入口）
	attr := src.attribute('/opt/homebrew/Cellar/node/24.1.0/bin/node') or {
		assert false
		return
	}
	assert attr.source_id == 'brew'
	assert attr.ecosystem == 'brew'
	assert attr.manager == 'brew'
}

// test_npm_attribute_and_enrich 假 fnm 安装 fixture：归因（包/node 本体/符号链接）与 enrich。
fn test_npm_attribute_and_enrich() {
	root := fixture_root('npm')
	inst_root := os.join_path(root, 'installation')
	bin_dir := os.join_path(inst_root, 'bin')
	mod_dir := os.join_path(inst_root, 'lib', 'node_modules')
	ts_bin := os.join_path(mod_dir, 'typescript', 'bin', 'tsc')
	node_bin := os.join_path(bin_dir, 'node')
	mkfake_exec(node_bin)
	mkfake_exec(ts_bin)
	mkfile(os.join_path(mod_dir, 'typescript', 'package.json'), '{"name":"typescript","version":"5.6.2","description":"TypeScript is a superset of JavaScript"}')
	// 坏 JSON 的包与无 package.json 的包：enrich 须跳过而非失败
	mkfake_exec(os.join_path(mod_dir, 'badjson', 'bin', 'bq'))
	mkfile(os.join_path(mod_dir, 'badjson', 'package.json'), '{oops not json')
	mkfake_exec(os.join_path(mod_dir, 'nopkgjson', 'bin', 'nq'))
	// scoped 包：目录形如 @<scope>/<name>，包名取两段
	scoped_bin := os.join_path(mod_dir, '@tools', 'cli', 'bin', 'cli')
	mkfake_exec(scoped_bin)
	mkfile(os.join_path(mod_dir, '@tools', 'cli', 'package.json'), '{"name":"@tools/cli","version":"1.4.0","description":"scoped cli tool"}')
	// bin/tsc 符号链接指向 node_modules 内的目标
	os.symlink(ts_bin, os.join_path(bin_dir, 'tsc')) or { panic(err) }
	src := NpmSource{
		installs: [NodeInstall{
			bin_dir:       bin_dir
			modules_dir:   mod_dir
			origin_prefix: 'fnm'
			scope:         'v22.12.0'
		}]
	}
	// roots / scopes
	assert src.roots() == [bin_dir]
	scopes := src.scopes()
	assert scopes.len == 1
	assert scopes[0].id == 'v22.12.0' && scopes[0].label == 'v22.12.0'
	// node 本体归因（bin 下且不经 node_modules）
	a1 := src.attribute(node_bin) or {
		assert false
		return
	}
	assert a1.source_id == 'npm'
	assert a1.ecosystem == 'node'
	assert a1.manager == 'fnm'
	assert a1.origin == 'node@fnm/v22.12.0'
	assert a1.scope == 'v22.12.0'
	// 包文件归因（node_modules 下）
	a2 := src.attribute(ts_bin) or {
		assert false
		return
	}
	assert a2.source_id == 'npm'
	assert a2.ecosystem == 'node'
	assert a2.manager == 'fnm'
	assert a2.origin == 'npm@fnm/v22.12.0'
	assert a2.scope == 'v22.12.0'
	// 符号链接 realpath 解析后落在 node_modules 下 → 包归因
	// （macOS 上 /tmp 会解析为 /private/tmp，故只断言后缀与归因结果）
	resolved := os.real_path(os.join_path(bin_dir, 'tsc'))
	assert resolved.ends_with('lib/node_modules/typescript/bin/tsc')
	a3 := src.attribute(resolved) or {
		assert false
		return
	}
	assert a3.origin == 'npm@fnm/v22.12.0'
	// 无关路径
	assert_none_attr(src.attribute('/usr/bin/ls'))
	assert_none_attr(src.attribute(os.join_path(root, 'elsewhere', 'bin', 'node')))
	// enrich
	mut entries := []model.Entry{}
	entries << model.Entry{
		name:      'tsc'
		source_id: 'npm'
		ecosystem: 'node'
		manager:   'fnm'
		origin:    'npm@fnm/v22.12.0'
		scope:     'v22.12.0'
		realpath:  ts_bin
	}
	entries << model.Entry{
		name:      'cli'
		source_id: 'npm'
		ecosystem: 'node'
		manager:   'fnm'
		origin:    'npm@fnm/v22.12.0'
		scope:     'v22.12.0'
		realpath:  scoped_bin
	}
	entries << model.Entry{
		name:      'bq'
		source_id: 'npm'
		ecosystem: 'node'
		manager:   'fnm'
		origin:    'npm@fnm/v22.12.0'
		scope:     'v22.12.0'
		realpath:  os.join_path(mod_dir, 'badjson', 'bin', 'bq')
	}
	entries << model.Entry{
		name:      'nq'
		source_id: 'npm'
		ecosystem: 'node'
		manager:   'fnm'
		origin:    'npm@fnm/v22.12.0'
		scope:     'v22.12.0'
		realpath:  os.join_path(mod_dir, 'nopkgjson', 'bin', 'nq')
	}
	entries << model.Entry{
		name:      'node'
		source_id: 'npm'
		ecosystem: 'node'
		manager:   'fnm'
		origin:    'node@fnm/v22.12.0'
		scope:     'v22.12.0'
		realpath:  node_bin
	}
	entries << model.Entry{
		name:      'ls'
		source_id: 'system'
		ecosystem: 'system'
		manager:   'system'
		realpath:  '/usr/bin/ls'
	}
	src.enrich(mut entries) or {
		assert false
		return
	}
	assert entries[0].version == '5.6.2'
	assert entries[0].description == 'TypeScript is a superset of JavaScript'
	assert entries[0].installed_at != ''
	assert entries[1].version == '1.4.0' // scoped 包取两段包名
	assert entries[1].description == 'scoped cli tool'
	assert entries[1].installed_at != ''
	assert entries[2].version == '' // 坏 JSON 跳过
	assert entries[2].installed_at == ''
	assert entries[3].version == '' // 缺 package.json 跳过
	assert entries[4].version == '22.12.0' // scope 去 'v'
	assert entries[4].description == 'Node.js 运行时'
	assert entries[5].version == '' // 非本源 entry 不动
}

// test_npm_multiple_installs 多安装并存：roots 过滤、scopes 汇总、按安装归因。
fn test_npm_multiple_installs() {
	root := fixture_root('npm-multi')
	r1 := os.join_path(root, 'fnm', 'v22.12.0', 'installation')
	r2 := os.join_path(root, 'nvm', 'v24.3.0')
	mkfake_exec(os.join_path(r1, 'bin', 'node'))
	mkfake_exec(os.join_path(r2, 'bin', 'node'))
	// 第三个安装的 bin 不存在：roots 应过滤，scopes 仍计入
	r3 := os.join_path(root, 'ghost')
	src := NpmSource{
		installs: [
			NodeInstall{
				bin_dir:       os.join_path(r1, 'bin')
				modules_dir:   os.join_path(r1, 'lib', 'node_modules')
				origin_prefix: 'fnm'
				scope:         'fnm/v22.12.0'
			},
			NodeInstall{
				bin_dir:       os.join_path(r2, 'bin')
				modules_dir:   os.join_path(r2, 'lib', 'node_modules')
				origin_prefix: 'nvm'
				scope:         'nvm/v24.3.0'
			},
			NodeInstall{
				bin_dir:       os.join_path(r3, 'bin')
				modules_dir:   os.join_path(r3, 'lib', 'node_modules')
				origin_prefix: 'fnm'
				scope:         'fnm/v9.9.9'
			},
		]
	}
	roots := src.roots()
	assert roots.len == 2
	assert os.join_path(r1, 'bin') in roots
	assert os.join_path(r2, 'bin') in roots
	scopes := src.scopes()
	assert scopes.len == 3
	assert scopes.map(it.id) == ['fnm/v22.12.0', 'nvm/v24.3.0', 'fnm/v9.9.9']
	// nvm 安装的 node 归因到 nvm scope
	a := src.attribute(os.join_path(r2, 'bin', 'node')) or {
		assert false
		return
	}
	assert a.origin == 'node@nvm/v24.3.0'
	assert a.scope == 'nvm/v24.3.0'
	// nvm 安装下 npm 包归因
	pkg_bin := os.join_path(r2, 'lib', 'node_modules', 'pnpm', 'bin', 'pnpm')
	a2 := src.attribute(pkg_bin) or {
		assert false
		return
	}
	assert a2.origin == 'npm@nvm/v24.3.0'
}

// test_conda_attribute_and_enrich 假 conda 环境 fixture：归因/scopes/enrich（conda-meta）。
fn test_conda_attribute_and_enrich() {
	root := fixture_root('conda')
	ml_bin := os.join_path(root, 'envs', 'ml', 'bin')
	meta_dir := os.join_path(root, 'envs', 'ml', 'conda-meta')
	mkfake_exec(os.join_path(ml_bin, 'python'))
	mkfake_exec(os.join_path(ml_bin, 'sqlite3'))
	mkfile(os.join_path(meta_dir, 'python-3.12.4-1.json'), '{"name":"python","version":"3.12.4","build":"1","files":["bin/python","bin/python3"]}')
	mkfile(os.join_path(meta_dir, 'sqlite-3.46.0-0.json'), '{"name":"sqlite","version":"3.46.0","build":"0","files":["bin/sqlite3","include/sqlite3.h"]}')
	// base 环境：只有 bin，无 conda-meta → enrich 跳过不失败
	base_bin := os.join_path(root, 'bin')
	mkfake_exec(os.join_path(base_bin, 'conda'))
	src := CondaSource{
		envs: [
			CondaEnv{ bin_dir: base_bin, manager: 'miniforge3', scope: 'base' },
			CondaEnv{ bin_dir: ml_bin, manager: 'miniforge3', scope: 'ml' },
		]
	}
	assert src.ecosystem() == 'python'
	assert src.id() == 'conda' && src.priority() == 30 && src.label() == 'conda'
	roots := src.roots()
	assert roots.len == 2
	assert base_bin in roots && ml_bin in roots
	scopes := src.scopes()
	assert scopes.map(it.id) == ['base', 'ml']
	// 环境内归因
	a := src.attribute(os.join_path(ml_bin, 'python')) or {
		assert false
		return
	}
	assert a.source_id == 'conda'
	assert a.ecosystem == 'python'
	assert a.manager == 'miniforge3'
	assert a.origin == 'miniforge3:ml'
	assert a.scope == 'ml'
	// base 归因
	ab := src.attribute(os.join_path(base_bin, 'conda')) or {
		assert false
		return
	}
	assert ab.origin == 'miniforge3:base'
	assert ab.manager == 'miniforge3'
	assert ab.scope == 'base'
	assert_none_attr(src.attribute('/usr/local/bin/git'))
	// enrich：meta 命中填版本与 meta mtime；base 无 meta 目录不受影响
	mut entries := []model.Entry{}
	entries << model.Entry{
		name:      'python'
		source_id: 'conda'
		ecosystem: 'python'
		manager:   'miniforge3'
		origin:    'miniforge3:ml'
		scope:     'ml'
		realpath:  os.join_path(ml_bin, 'python')
	}
	entries << model.Entry{
		name:      'sqlite3'
		source_id: 'conda'
		ecosystem: 'python'
		manager:   'miniforge3'
		origin:    'miniforge3:ml'
		scope:     'ml'
		realpath:  os.join_path(ml_bin, 'sqlite3')
	}
	entries << model.Entry{
		name:      'unknown'
		source_id: 'conda'
		ecosystem: 'python'
		manager:   'miniforge3'
		origin:    'miniforge3:ml'
		scope:     'ml'
		realpath:  os.join_path(ml_bin, 'unknown')
	}
	entries << model.Entry{
		name:      'conda'
		source_id: 'conda'
		ecosystem: 'python'
		manager:   'miniforge3'
		origin:    'miniforge3:base'
		scope:     'base'
		realpath:  os.join_path(base_bin, 'conda')
	}
	src.enrich(mut entries) or {
		assert false
		return
	}
	assert entries[0].version == '3.12.4'
	assert entries[0].installed_at != ''
	assert entries[0].description == '' // conda 描述留空
	assert entries[1].version == '3.46.0'
	assert entries[2].version == '' // bin 不在任何包 files 中
	assert entries[3].version == '' // base 无 conda-meta，跳过
}

// test_uv_attribute_and_enrich 假 uv tools 与 python fixture：归因/scopes/enrich。
fn test_uv_attribute_and_enrich() {
	root := fixture_root('uv')
	tools_dir := os.join_path(root, 'tools')
	python_dir := os.join_path(root, 'python')
	local_bin := os.join_path(root, 'bin')
	kimi_bin := os.join_path(tools_dir, 'kimi-cli', 'bin', 'kimi')
	py_bin := os.join_path(python_dir, 'cpython-3.11', 'bin', 'python3.11')
	uv_bin := os.join_path(local_bin, 'uv')
	mkfake_exec(kimi_bin)
	mkfake_exec(py_bin)
	mkfake_exec(uv_bin)

	src := UvSource{
		tools_dir:  tools_dir
		python_dir: python_dir
		local_bin:  local_bin
	}

	assert src.ecosystem() == 'python'
	assert src.id() == 'uv'
	assert src.label() == 'uv'
	assert src.priority() == 25

	// 1. 工具归因
	a_tool := src.attribute(kimi_bin) or {
		assert false
		return
	}
	assert a_tool.source_id == 'uv'
	assert a_tool.ecosystem == 'python'
	assert a_tool.manager == 'uv'
	assert a_tool.scope == 'tools'
	assert a_tool.origin == 'uv:tool/kimi-cli'

	// 2. Python 运行时工具链归因
	a_py := src.attribute(py_bin) or {
		assert false
		return
	}
	assert a_py.ecosystem == 'python'
	assert a_py.manager == 'uv'
	assert a_py.scope == 'toolchain'
	assert a_py.origin == 'uv:python'

	// 3. uv 本身归因
	a_uv := src.attribute(uv_bin) or {
		assert false
		return
	}
	assert a_uv.ecosystem == 'python'
	assert a_uv.manager == 'uv'
	assert a_uv.scope == 'tools'
	assert a_uv.origin == 'uv:self'

	// 4. 非 uv 路径
	assert_none_attr(src.attribute('/usr/bin/python'))
}

// test_cargo_attribute_and_enrich 假 .crates2.json fixture：归因/enrich/文件缺失降级。
fn test_cargo_attribute_and_enrich() {
	root := fixture_root('cargo')
	bin := os.join_path(root, 'bin')
	mkfake_exec(os.join_path(bin, 'rg'))
	mkfake_exec(os.join_path(bin, 'custom-tool'))
	mkfake_exec(os.join_path(bin, 'mystery'))
	c2 := os.join_path(root, '.crates2.json')
	mkfile(c2, '{"installs":{"ripgrep 14.1.0 (registry+https://github.com/rust-lang/crates.io-index)":{"bins":["rg"]},"xtask 0.1.0 (registry+https://github.com/rust-lang/crates.io-index)":{"bins":["custom-tool","extra"]}}}')
	src := CargoSource{ root: bin, crates2_path: c2 }
	assert src.ecosystem() == 'rust'
	assert src.id() == 'cargo' && src.priority() == 40 && src.label() == 'cargo'
	assert src.roots() == [bin]
	assert src.scopes().len == 0
	a := src.attribute(os.join_path(bin, 'rg')) or {
		assert false
		return
	}
	assert a.source_id == 'cargo' && a.ecosystem == 'rust' && a.manager == 'cargo' && a.origin == 'cargo' && a.scope == ''
	assert_none_attr(src.attribute('/usr/local/bin/git'))
	assert_none_attr(src.attribute(bin)) // 恰为根目录本身不算
	// enrich
	mut entries := []model.Entry{}
	entries << model.Entry{
		name:      'rg'
		source_id: 'cargo'
		ecosystem: 'rust'
		manager:   'cargo'
		origin:    'cargo'
		realpath:  os.join_path(bin, 'rg')
	}
	entries << model.Entry{
		name:      'custom-tool'
		source_id: 'cargo'
		ecosystem: 'rust'
		manager:   'cargo'
		origin:    'cargo'
		realpath:  os.join_path(bin, 'custom-tool')
	}
	entries << model.Entry{
		name:      'mystery'
		source_id: 'cargo'
		ecosystem: 'rust'
		manager:   'cargo'
		origin:    'cargo'
		realpath:  os.join_path(bin, 'mystery')
	}
	src.enrich(mut entries) or {
		assert false
		return
	}
	assert entries[0].version == '14.1.0'
	assert entries[0].installed_at != '' // 二进制 mtime
	assert entries[1].version == '0.1.0'
	assert entries[2].version == '' // 不在 bins 中
	// crates2 缺失：整体跳过不失败
	missing := CargoSource{ root: bin, crates2_path: os.join_path(root, 'nope.json') }
	mut es2 := []model.Entry{}
	es2 << model.Entry{
		name:      'rg'
		source_id: 'cargo'
		ecosystem: 'rust'
		manager:   'cargo'
		origin:    'cargo'
		realpath:  os.join_path(bin, 'rg')
	}
	missing.enrich(mut es2) or {
		assert false
		return
	}
	assert es2[0].version == ''
	assert es2[0].installed_at == ''
	// root 未设置（未发现 cargo）时 attribute 恒 none
	empty := CargoSource{}
	assert empty.roots() == []
	assert_none_attr(empty.attribute(os.join_path(bin, 'rg')))
}

// test_go_attribute_and_enrich 假 go bin fixture：归因；enrich 对非 Go 二进制静默留空。
fn test_go_attribute_and_enrich() {
	root := fixture_root('go')
	mkfake_exec(os.join_path(root, 'bin', 'dlv'))
	src := GoSource{
		roots: [os.join_path(root, 'bin')]
	}
	assert src.ecosystem() == 'go'
	assert src.id() == 'go' && src.priority() == 50 && src.label() == 'Go'
	assert src.roots() == [os.join_path(root, 'bin')]
	assert src.scopes().len == 2
	a := src.attribute(os.join_path(root, 'bin', 'dlv')) or {
		assert false
		return
	}
	assert a.source_id == 'go' && a.ecosystem == 'go' && a.manager == 'go' && a.origin == 'go:gopath' && a.scope == 'gopath'
	assert_none_attr(src.attribute('/usr/local/bin/git'))
	// enrich：fixture 二进制非 Go 产物 → 无 mod 行 → version 留空且不报错
	// （真机有 go 时逐条调用返回无 mod 行；无 go 时整体跳过；两种环境下断言一致）
	mut entries := []model.Entry{}
	entries << model.Entry{
		name:      'dlv'
		source_id: 'go'
		ecosystem: 'go'
		manager:   'go'
		origin:    'go:gopath'
		scope:     'gopath'
		realpath:  os.join_path(root, 'bin', 'dlv')
	}
	entries << model.Entry{
		name:      'ls'
		source_id: 'system'
		ecosystem: 'system'
		manager:   'system'
		realpath:  '/usr/bin/ls'
	}
	src.enrich(mut entries) or {
		assert false
		return
	}
	assert entries[0].version == ''
	// root 未设置（未发现 GOPATH/bin）时 attribute 恒 none
	empty := GoSource{}
	assert empty.roots() == []
	assert_none_attr(empty.attribute(os.join_path(root, 'bin', 'dlv')))
}

// test_pnpm_attribute_and_enrich 假 pnpm fixture：归因与从 package.json 提取元数据。
fn test_pnpm_attribute_and_enrich() {
	root := fixture_root('pnpm')
	pnpm_home := os.join_path(root, 'pnpm_home')
	mkfake_exec(os.join_path(pnpm_home, 'appium'))
	mkfake_exec(os.join_path(pnpm_home, 'ports'))
	global_5 := os.join_path(pnpm_home, 'global', '5', 'node_modules')
	mkfile(os.join_path(global_5, 'appium', 'package.json'), '{"name":"appium","version":"3.1.2","description":"Automation for Apps.","bin":"index.js"}')
	mkfile(os.join_path(global_5, 'port-whisperer', 'package.json'), '{"name":"port-whisperer","version":"1.3.0","description":"Port viewer","bin":{"ports":"./bin.js"}}')

	src := PnpmSource{
		root:       pnpm_home
		global_dir: os.join_path(pnpm_home, 'global')
	}
	assert src.ecosystem() == 'node'
	assert src.id() == 'pnpm' && src.priority() == 7 && src.label() == 'pnpm'
	assert src.roots() == [pnpm_home]
	assert src.scopes().len == 0

	a := src.attribute(os.join_path(pnpm_home, 'appium')) or {
		assert false
		return
	}
	assert a.source_id == 'pnpm' && a.ecosystem == 'node' && a.manager == 'pnpm' && a.origin == 'pnpm:global' && a.scope == ''
	assert_none_attr(src.attribute('/usr/local/bin/git'))

	mut entries := []model.Entry{}
	entries << model.Entry{
		name:      'appium'
		source_id: 'pnpm'
		ecosystem: 'node'
		manager:   'pnpm'
		origin:    'pnpm:global'
		realpath:  os.join_path(pnpm_home, 'appium')
	}
	entries << model.Entry{
		name:      'ports'
		source_id: 'pnpm'
		ecosystem: 'node'
		manager:   'pnpm'
		origin:    'pnpm:global'
		realpath:  os.join_path(pnpm_home, 'ports')
	}
	src.enrich(mut entries) or {
		assert false
		return
	}
	assert entries[0].version == '3.1.2'
	assert entries[0].description == 'Automation for Apps.'
	assert entries[1].version == '1.3.0'
	assert entries[1].description == 'Port viewer'

	empty := PnpmSource{}
	assert empty.roots() == []
	assert_none_attr(empty.attribute(os.join_path(pnpm_home, 'appium')))
}
