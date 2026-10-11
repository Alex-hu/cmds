// simple_sources_test.v —— 四个简单来源的单元测试。
// 全部基于临时目录树 fixture 伪造，不依赖真机安装状态；
// 仅 new_rvm_source/new_app_source_auto 等真实机器构造函数做无害的发现性断言。
module source

import os
import internal.model

// new_fixture_base 建立干净的临时 fixture 根目录（按 pid 隔离，重复运行先清理）。
fn new_fixture_base() !string {
	base := os.join_path(os.temp_dir(), 'cmds_simple_sources_${os.getpid()}')
	if os.exists(base) {
		os.rmdir_all(base)!
	}
	os.mkdir_all(base, mode: 0o755)!
	return base
}

// make_exec 在 dir 下创建名为 name、权限 0o755 的可执行脚本文件。
fn make_exec(dir string, name string) !string {
	os.mkdir_all(dir, mode: 0o755)!
	exe := os.join_path(dir, name)
	os.write_file(exe, '#!/bin/sh\nexit 0\n')!
	os.chmod(exe, 0o755)!
	return exe
}

// ---------------------------------------------------------------------------
// SystemSource
// ---------------------------------------------------------------------------

fn test_system_source_meta() {
	s := new_system_source()
	assert s.id() == 'system'
	assert s.label() == '系统'
	assert s.priority() == 100
	assert s.scopes().len == 0
	// enrich 是 no-op：条目原样返回
	mut entries := [model.Entry{ name: 'ls', source: 'system', realpath: '/bin/ls' }]
	s.enrich(mut entries) or { assert false }
	assert entries.len == 1
	assert entries[0].name == 'ls'
	assert entries[0].version == ''
}

fn test_system_source_roots() {
	s := new_system_source()
	roots := s.roots()
	assert roots.len > 0 // macOS 至少存在 /bin、/usr/bin
	for r in roots {
		assert r in system_bin_dirs // 只来自固定候选清单
		assert os.is_dir(r) // 且真实存在
	}
}

fn test_system_source_attribute_hit() {
	s := new_system_source()
	// 规格:/usr/bin/ls → Attribution{'system','system',''}
	if a := s.attribute('/usr/bin/ls') {
		assert a.source == 'system'
		assert a.origin == 'system'
		assert a.scope == '' // 空串=无二级分类
	} else {
		assert false
	}
	// 四个候选目录的前缀都应命中（attribute 不依赖目录当前是否存在）
	for d in system_bin_dirs {
		if a := s.attribute(d + '/ls') {
			assert a.source == 'system'
		} else {
			assert false
		}
	}
}

fn test_system_source_attribute_miss() {
	s := new_system_source()
	mut none_count := 0
	// 规格:/usr/local/bin/x → none（非系统目录）
	if _ := s.attribute('/usr/local/bin/x') {
		assert false
	} else {
		none_count++
	}
	// 前缀必须整目录匹配:'/binx/ls' 不以 '/bin/' 开头
	if _ := s.attribute('/binx/ls') {
		assert false
	} else {
		none_count++
	}
	// 恰好等于目录本身（无尾部 '/'）也不算目录之下
	if _ := s.attribute('/usr/bin') {
		assert false
	} else {
		none_count++
	}
	assert none_count == 3
}

// ---------------------------------------------------------------------------
// RvmSource
// ---------------------------------------------------------------------------

fn test_rvm_source_fixture_root() ! {
	base := new_fixture_base()!
	defer {
		os.rmdir_all(base) or { assert false }
	}
	rvm_bin := os.join_path(base, '.rvm', 'bin')
	exe := make_exec(rvm_bin, 'ruby')!
	assert exe != ''

	s := RvmSource{ root: rvm_bin }
	assert s.id() == 'rvm'
	assert s.label() == 'rvm'
	assert s.priority() == 60
	assert s.scopes().len == 0
	assert s.roots() == [rvm_bin]
	if a := s.attribute(os.join_path(rvm_bin, 'ruby')) {
		assert a.source == 'rvm'
		assert a.origin == 'rvm'
		assert a.scope == ''
	} else {
		assert false
	}
	// 前缀必须整目录匹配:'.../binx/...' 不命中
	if _ := s.attribute(rvm_bin + 'x/ruby') {
		assert false
	}
	// 其他目录不归因
	if _ := s.attribute('/usr/local/bin/ruby') {
		assert false
	}
	// enrich 是 no-op
	mut entries := [model.Entry{ name: 'ruby', source: 'rvm' }]
	s.enrich(mut entries) or { assert false }
	assert entries.len == 1
}

fn test_rvm_source_empty_root() {
	s := RvmSource{}
	assert s.roots().len == 0 // root 为空 → 无发现根
	// root 为空（本机未装 RVM）时不归因任何路径
	if _ := s.attribute('/Users/x/.rvm/bin/ruby') {
		assert false
	}
}

fn test_new_rvm_source_real_machine() {
	s := new_rvm_source()
	if s.root != '' {
		// 装了 RVM：root 必须是 ~/.rvm/bin 且真实存在
		assert s.root == os.join_path(os.home_dir(), '.rvm', 'bin')
		assert os.is_dir(s.root)
		assert s.roots() == [s.root]
	} else {
		// 未装 RVM：root 为空串、无发现根
		assert s.roots().len == 0
	}
}

// ---------------------------------------------------------------------------
// AppSource
// ---------------------------------------------------------------------------

fn test_app_source_from_path_env() ! {
	base := new_fixture_base()!
	defer {
		os.rmdir_all(base) or { assert false }
	}
	// fixture:真建出 .app bundle 内的命令目录与可执行文件
	tools := os.join_path(base, 'Fake.app', 'Contents', 'MacOS', 'tools')
	exe := make_exec(tools, 'fakecli')!
	assert exe != ''
	normal_bin := os.join_path(base, 'normalbin')
	os.mkdir_all(normal_bin, mode: 0o755)!

	// PATH 混入:bundle 目录、普通目录、不存在的目录、非 bundle 形状目录
	path_env := [
		tools,
		normal_bin,
		os.join_path(base, 'missing', 'Bar.app', 'Contents', 'MacOS'),
		os.join_path(base, 'NotBundle', 'Contents', 'MacOS'),
	].join(':')
	s := new_app_source(path_env)
	assert s.id() == 'app'
	assert s.label() == 'app'
	assert s.priority() == 70
	assert s.scopes().len == 0
	// 只收集 bundle 内目录，且按 realpath 归一化
	assert s.app_dirs.len == 1
	assert s.roots() == [os.real_path(tools)]
	// 归因:origin == 'app:Fake'（bundle 名去掉 .app 后缀）
	cli := os.join_path(tools, 'fakecli')
	if a := s.attribute(cli) {
		assert a.source == 'app'
		assert a.origin == 'app:Fake'
		assert a.scope == ''
	} else {
		assert false
	}
	// enrich 是 no-op
	mut entries := [model.Entry{ name: 'fakecli', source: 'app' }]
	s.enrich(mut entries) or { assert false }
	assert entries.len == 1
}

fn test_app_source_attribute_bundle_shapes() {
	s := new_app_source('')
	// roots 为空不影响 attribute 的纯路径形状判定
	if a := s.attribute('/Applications/Fake.app/Contents/MacOS/tools/fakecli') {
		assert a.source == 'app'
		assert a.origin == 'app:Fake'
	} else {
		assert false
	}
	// bundle 名自身含 '.app'：只剥最后一层后缀
	if a := s.attribute('/Applications/My.App.app/Contents/MacOS/t') {
		assert a.origin == 'app:My.App'
	} else {
		assert false
	}
	// 非 bundle 路径不归因
	if _ := s.attribute('/usr/local/bin/node') {
		assert false
	}
	// '.app' 后接的不是 'Contents' 不算 bundle 内路径
	if _ := s.attribute('/Applications/Fake.app/Frameworks/x/bin/t') {
		assert false
	}
}

fn test_new_app_source_auto_real_machine() {
	s := new_app_source_auto() // 按真实 PATH 发现，不依赖安装状态
	for d in s.app_dirs {
		assert d.contains('.app/Contents/')
		assert os.is_dir(d)
	}
}

// ---------------------------------------------------------------------------
// ManualSource
// ---------------------------------------------------------------------------

fn test_manual_source_filtering() ! {
	base := new_fixture_base()!
	defer {
		os.rmdir_all(base) or { assert false }
	}
	dir_a := os.join_path(base, 'a')
	dir_b := os.join_path(base, 'b')
	dir_taken := os.join_path(base, 'taken')
	exe := make_exec(dir_a, 'tool')!
	assert exe != ''
	os.mkdir_all(dir_b, mode: 0o755)!
	os.mkdir_all(dir_taken, mode: 0o755)!
	// 符号链接指向 dir_a：同一目录以两种路径串出现
	dir_link := os.join_path(base, 'link')
	os.symlink(dir_a, dir_link)!

	missing := os.join_path(base, 'missing')
	taken_rp := os.real_path(dir_taken)

	// PATH 混入:重复目录（含符号链接形态）、不存在的目录、被 taken 占用的目录
	path_env := [dir_a, dir_link, dir_a, missing, dir_taken, dir_b].join(':')
	m := new_manual_source(path_env, [taken_rp])
	assert m.id() == 'manual'
	assert m.priority() == 999
	// realpath 去重:dir_a 与其符号链接合并为一条；missing 跳过；taken（realpath 占用）跳过
	assert m.root_dirs == [os.real_path(dir_a), os.real_path(dir_b)]
	assert m.roots() == m.root_dirs
}

fn test_manual_source_taken_by_raw_string() ! {
	base := new_fixture_base()!
	defer {
		os.rmdir_all(base) or { assert false }
	}
	dir_a := os.join_path(base, 'a')
	os.mkdir_all(dir_a, mode: 0o755)!
	dir_b := os.join_path(base, 'b')
	os.mkdir_all(dir_b, mode: 0o755)!
	// taken 里放的是目录原始串（而非 realpath）：同样过滤
	m := new_manual_source([dir_a, dir_b].join(':'), [dir_a])
	assert m.root_dirs == [os.real_path(dir_b)]
}

fn test_manual_source_attribute_always_none() ! {
	base := new_fixture_base()!
	defer {
		os.rmdir_all(base) or { assert false }
	}
	dir_a := os.join_path(base, 'a')
	exe := make_exec(dir_a, 'tool')!
	assert exe != ''
	m := new_manual_source(dir_a, [])
	assert m.label() == 'manual'
	assert m.scopes().len == 0
	// 兜底源永不归因：由 update 管道统一处理
	if _ := m.attribute(os.join_path(dir_a, 'tool')) {
		assert false
	}
	if _ := m.attribute('/usr/bin/ls') {
		assert false
	}
	// enrich 是 no-op
	mut entries := [model.Entry{ name: 'tool', source: 'manual' }]
	m.enrich(mut entries) or { assert false }
	assert entries.len == 1
}

// ---------------------------------------------------------------------------
// 接口一致性
// ---------------------------------------------------------------------------

fn test_interface_conformance() {
	// 四个实现都能装进 []Source 并动态分发
	mut srcs := []Source{}
	srcs << new_system_source()
	srcs << new_rvm_source()
	srcs << new_app_source(os.getenv('PATH'))
	srcs << new_manual_source(os.getenv('PATH'), [])
	assert srcs.len == 4
	ids := srcs.map(it.id())
	assert ids.contains('system')
	assert ids.contains('rvm')
	assert ids.contains('app')
	assert ids.contains('manual')
	labels := srcs.map(it.label())
	assert labels.contains('系统')
	// enrich/scopes 经接口调用也是 no-op/空
	mut entries := []model.Entry{}
	for mut s in srcs {
		s.enrich(mut entries) or { assert false }
		assert s.scopes().len == 0
	}
}

fn test_priority_ordering() {
	// 具体源在前、system 居中、manual 兜底:rvm(60) < app(70) < system(100) < manual(999)
	assert new_rvm_source().priority() < new_app_source('').priority()
	assert new_app_source('').priority() < new_system_source().priority()
	assert new_system_source().priority() < new_manual_source('', []).priority()
}
