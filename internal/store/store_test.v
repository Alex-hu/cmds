module store

import internal.model
import os

// e1：带 2 个 occurrences 且 path_priority 乱序（5 在前 2 在后，读回应升序）。
fn e1() model.Entry {
	return model.Entry{
		name:         'tsc'
		source_id:    'npm'
		ecosystem:    'node'
		manager:      'fnm'
		origin:       'fnm:v22.12.0'
		realpath:     '/n/tsc'
		in_path:      true
		occurrences:  [
			model.Occurrence{ path: '/b/tsc', path_priority: 5 },
			model.Occurrence{ path: '/a/tsc', path_priority: 2 },
		]
		version:      '5.6.3'
		description:  'TypeScript compiler'
		installed_at: '2026-09-01 10:30'
		size_bytes:   0
		kind:         'binary'
	}
}

// e2：scope 非空的 conda 条目。
fn e2() model.Entry {
	return model.Entry{
		name:         'jupyter'
		source_id:    'conda'
		ecosystem:    'python'
		manager:      'conda'
		origin:       'conda:miniforge3/envs/ml'
		scope:        'miniforge3/envs/ml'
		realpath:     '/m/jupyter'
		in_path:      false
		occurrences:  [
			model.Occurrence{ path: '/m/jupyter', path_priority: 0 },
		]
		installed_at: '2026-08-15 09:00'
		kind:         'script'
	}
}

// e3：size/kind 取典型值（大文件尺寸覆盖 get_int 32 位截断边界）。
fn e3() model.Entry {
	return model.Entry{
		name:         'git'
		source_id:    'brew'
		ecosystem:    'brew'
		manager:      'brew'
		origin:       'brew'
		realpath:     '/usr/local/bin/git'
		in_path:      true
		occurrences:  [
			model.Occurrence{ path: '/usr/local/bin/git', path_priority: 7 },
		]
		version:      '2.46.0'
		description:  'Distributed version control system'
		installed_at: '2026-07-20 16:45'
		size_bytes:   53687061234
		kind:         'binary'
	}
}

fn test_round_trip() {
	mut s := open(':memory:')!
	defer {
		s.close()
	}
	s.save_all([e1(), e2(), e3()])!
	got := s.load_all()!
	assert got.len == 3
	// 逐条按 realpath 找回后逐字段断言（load_all 按 name、realpath 排序，不依赖写入顺序）
	g1 := got.filter(it.realpath == '/n/tsc')[0]
	assert g1.name == 'tsc'
	assert g1.source_id == 'npm'
	assert g1.ecosystem == 'node'
	assert g1.manager == 'fnm'
	assert g1.origin == 'fnm:v22.12.0'
	assert g1.scope == ''
	assert g1.in_path == true
	assert g1.version == '5.6.3'
	assert g1.description == 'TypeScript compiler'
	assert g1.installed_at == '2026-09-01 10:30'
	assert g1.size_bytes == 0
	assert g1.kind == 'binary'
	assert g1.occurrences.len == 2
	assert g1.occurrences[0].path_priority == 2 // 乱序写入，读回按 path_priority 升序
	assert g1.occurrences[0].path == '/a/tsc'
	assert g1.occurrences[1].path_priority == 5
	assert g1.occurrences[1].path == '/b/tsc'

	g2 := got.filter(it.realpath == '/m/jupyter')[0]
	assert g2.ecosystem == 'python'
	assert g2.manager == 'conda'
	assert g2.scope == 'miniforge3/envs/ml' // 非空 scope 往返
	assert g2.in_path == false
	assert g2.version == '' // 空串往返（库里为 NULL）
	assert g2.description == ''
	assert g2.size_bytes == 0
	assert g2.occurrences.len == 1
	assert g2.occurrences[0].path == '/m/jupyter'

	g3 := got.filter(it.realpath == '/usr/local/bin/git')[0]
	assert g3.ecosystem == 'brew'
	assert g3.manager == 'brew'
	assert g3.size_bytes == 53687061234 // u64 大值往返（> 2^31）
	assert g3.kind == 'binary'
	assert g3.version == '2.46.0'
}

fn test_save_all_replaces_previous_index() {
	mut s := open(':memory:')!
	defer {
		s.close()
	}
	s.save_all([e1(), e2(), e3()])!
	s.save_all([e3()])! // 全量替换：旧数据应全部清空
	got := s.load_all()!
	assert got.len == 1
	assert got[0].realpath == '/usr/local/bin/git'
	if v := s.meta_get('count') {
		assert v == '1'
	} else {
		assert false
	}
}

fn test_query_filters() {
	mut s := open(':memory:')!
	defer {
		s.close()
	}
	s.save_all([e1(), e2(), e3()])!
	// 空参 = 全量
	assert s.query('', '', '', '')!.len == 3
	// 按 ecosystem 过滤
	by_eco := s.query('python', '', '', '')!
	assert by_eco.len == 1
	assert by_eco[0].name == 'jupyter'
	// 按 manager 过滤
	by_mgr := s.query('', 'conda', '', '')!
	assert by_mgr.len == 1
	assert by_mgr[0].name == 'jupyter'
	// 按 scope 过滤
	by_scope := s.query('', '', 'miniforge3/envs/ml', '')!
	assert by_scope.len == 1
	assert by_scope[0].manager == 'conda'
	// 组合过滤
	assert s.query('python', 'conda', 'miniforge3/envs/ml', '')!.len == 1
	assert s.query('brew', 'brew', 'miniforge3/envs/ml', '')!.len == 0
	// 按 name_contains 过滤（LIKE 子串）
	by_name := s.query('', '', '', 'py')!
	assert by_name.len == 1
	assert by_name[0].name == 'jupyter'
	assert s.query('', '', '', 'zzz')!.len == 0
}

fn test_meta_get() {
	mut s := open(':memory:')!
	defer {
		s.close()
	}
	if s.meta_get('built_at') != none {
		assert false // 未 save 前无 built_at
	}
	s.save_all([e1(), e2(), e3()])!
	if v := s.meta_get('built_at') {
		assert v != '' // built_at 存在且非空
	} else {
		assert false
	}
	if v := s.meta_get('count') {
		assert v == '3'
	} else {
		assert false
	}
	if s.meta_get('no_such_key') != none {
		assert false // 不存在的 key 返回 none
	}
}

fn test_schema_version_mismatch_rebuilds() {
	path := os.join_path(os.temp_dir(), 'cmds_store_test_migration.db')
	if os.exists(path) {
		os.rm(path) or { panic(err) }
	}
	mut s := open(path)! // 第一次 open：空文件 → 建 v1 schema
	defer {
		if os.exists(path) {
			os.rm(path) or { panic(err) }
		}
	}
	s.save_all([e1(), e2(), e3()])!
	assert s.load_all()!.len == 3
	// 模拟未来版本写的库：手动抬高 user_version 后关闭
	s.db.exec_none('PRAGMA user_version = 99')
	assert s.db.q_int('pragma user_version')! == 99
	s.close()
	// 重新 open 同一文件：应静默 drop 重建为当前 schema，不报错且旧数据清空
	mut s2 := open(path)!
	assert s2.db.q_int('pragma user_version')! == schema_version
	assert s2.load_all()!.len == 0
	if s2.meta_get('built_at') != none {
		assert false // meta 也随重建清空
	}
	// 重建后的库可正常继续使用
	s2.save_all([e2()])!
	assert s2.query('python', 'conda', '', '')!.len == 1
	s2.close()
}
