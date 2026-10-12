module model

fn mk(name string, eco string, mgr string, realpath string, prio int) Entry {
	return Entry{
		name:        name
		source_id:   mgr
		ecosystem:   eco
		manager:     mgr
		origin:      '${eco}:${mgr}'
		realpath:    realpath
		in_path:     true
		occurrences: [Occurrence{ path: '/x/' + name, path_priority: prio }]
	}
}

fn test_dedupe_merges_same_file() {
	a := mk('tsc', 'node', 'fnm', '/n/tsc', 3)
	mut b := mk('tsc', 'node', 'fnm', '/n/tsc', 7)
	b.occurrences = [Occurrence{ path: '/y/tsc', path_priority: 7 }]
	c := mk('tsc', 'node', 'fnm', '/m/tsc', 1)
	out := dedupe([a, b, c])
	assert out.len == 2
	merged := out.filter(it.realpath == '/n/tsc')[0]
	assert merged.occurrences.len == 2
	assert merged.occurrences[0].path_priority == 3
}

fn test_merge_by_name_keeps_order() {
	out := merge_by_name([mk('b', 'x', 'x', '/b', 1), mk('a', 'x', 'x', '/a', 2),
		mk('b', 'y', 'y', '/c', 3)])
	assert out.len == 2
	assert out[0].name == 'b' && out[0].providers.len == 2
	assert out[1].name == 'a'
}

fn test_filters() {
	es := [
		mk('tsc', 'node', 'fnm', '/a', 1),
		mk('pnpm', 'node', 'pnpm', '/p', 1),
		mk('git', 'brew', 'brew', '/b', 2),
		mk('jupyter', 'python', 'conda', '/c', 3),
	]
	mut m := es.clone()
	m[3].scope = 'miniforge3/envs/ml'
	m[3].description = 'Notebook'

	assert filter_by_ecosystem(es, 'node').len == 2
	assert filter_by_ecosystem(es, '').len == 4
	assert filter_by_manager(es, 'fnm').len == 1
	assert filter_by_manager(es, 'pnpm').len == 1
	assert filter_by_source(es, 'brew').len == 1
	assert filter_by_source(es, 'node').len == 2
	assert filter_by_source(es, '').len == 4
	assert filter_by_scope(m, 'miniforge3/envs/ml').len == 1
	assert filter_by_scope(m, '').len == 4
	assert filter_by_text(m, 'note').len == 1
	assert filter_by_text(m, 'TSC').len == 1
	assert filter_by_text(m, 'zzz').len == 0
}

fn test_fuzzy_score() {
	if s := fuzzy_score('', 'any') {
		assert s == 0
	} else {
		assert false
	}
	if s := fuzzy_score('tsc', 'tsc') {
		assert s > 0
	} else {
		assert false
	}
	if s := fuzzy_score('tsc', 'typescript compiler') { // 子序列 t-s-c
		assert s > 0
	} else {
		assert false
	}
	if fuzzy_score('zzz', 'tsc') != none {
		assert false
	}
	// 连续命中应比分散命中得分高
	con := fuzzy_score('ab', 'abxx') or { 0 }
	dis := fuzzy_score('ab', 'axbx') or { 0 }
	assert con > dis
}

fn test_action_guidance() {
	// 1. in_path 为 true：直接运行命令名，无需切换环境
	e_path := Entry{
		name:      'git'
		in_path:   true
		realpath:  '/usr/local/bin/git'
		ecosystem: 'brew'
		manager:   'brew'
	}
	htr1, se1 := action_guidance(e_path)
	assert htr1 == 'git'
	assert se1 == ''

	// 2. conda 环境未在 PATH：提示 conda activate
	e_conda := Entry{
		name:      'jupyter'
		in_path:   false
		realpath:  '/Users/alex/anaconda3/envs/myenv/bin/jupyter'
		ecosystem: 'python'
		manager:   'anaconda3'
		scope:     'myenv'
	}
	htr2, se2 := action_guidance(e_conda)
	assert htr2 == '/Users/alex/anaconda3/envs/myenv/bin/jupyter'
	assert se2 == 'conda activate myenv'

	// 3. fnm 未在 PATH：提示 fnm use
	e_fnm := Entry{
		name:      'tsc'
		in_path:   false
		realpath:  '/n/tsc'
		ecosystem: 'node'
		manager:   'fnm'
		scope:     'v24.11.1'
	}
	htr3, se3 := action_guidance(e_fnm)
	assert htr3 == '/n/tsc'
	assert se3 == 'fnm use v24.11.1'

	// 4. uv 工具：提示 uv run
	e_uv := Entry{
		name:      'kimi'
		in_path:   false
		realpath:  '/u/kimi'
		ecosystem: 'python'
		manager:   'uv'
		scope:     'tools'
	}
	htr4, se4 := action_guidance(e_uv)
	assert htr4 == '/u/kimi'
	assert se4 == 'uv run kimi'
}

fn test_rank_search() {
	entries := [
		Entry{
			name:        'agent-browser'
			description: 'Browser automation CLI for AI agents'
			ecosystem:   'node'
			manager:     'fnm'
			scope:       'v24.11.1'
			in_path:     true
			realpath:    '/bin/agent-browser'
		},
		Entry{
			name:        'agent'
			description: 'Cursor agent runner'
			ecosystem:   'manual'
			manager:     'manual'
			in_path:     false
			realpath:    '/bin/agent'
		},
		Entry{
			name:        'jupyter'
			description: 'Jupyter Notebook'
			ecosystem:   'python'
			manager:     'anaconda3'
			scope:       'myenv'
			in_path:     false
			realpath:    '/bin/jupyter'
		},
	]

	// 精确匹配 'agent'：完全相等的 'agent' 应该排在 'agent-browser' 之前
	res1 := rank_search(entries, 'agent')
	assert res1.len == 2
	assert res1[0].entry.name == 'agent'
	assert res1[1].entry.name == 'agent-browser'

	// 多词匹配 'agent browser'：仅匹配包含两个词的条目
	res2 := rank_search(entries, 'agent browser')
	assert res2.len == 1
	assert res2[0].entry.name == 'agent-browser'

	// 空查询返回全部
	res_empty := rank_search(entries, '')
	assert res_empty.len == 3
}
