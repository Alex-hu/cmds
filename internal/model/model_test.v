module model

fn mk(name string, source string, realpath string, prio int) Entry {
	return Entry{
		name:        name
		source:      source
		origin:      source
		realpath:    realpath
		in_path:     true
		occurrences: [Occurrence{ path: '/x/' + name, path_priority: prio }]
	}
}

fn test_dedupe_merges_same_file() {
	a := mk('tsc', 'npm', '/n/tsc', 3)
	mut b := mk('tsc', 'npm', '/n/tsc', 7)
	b.occurrences = [Occurrence{ path: '/y/tsc', path_priority: 7 }]
	c := mk('tsc', 'npm', '/m/tsc', 1)
	out := dedupe([a, b, c])
	assert out.len == 2
	merged := out.filter(it.realpath == '/n/tsc')[0]
	assert merged.occurrences.len == 2
	assert merged.occurrences[0].path_priority == 3
}

fn test_merge_by_name_keeps_order() {
	out := merge_by_name([mk('b', 'x', '/b', 1), mk('a', 'x', '/a', 2), mk('b', 'y', '/c', 3)])
	assert out.len == 2
	assert out[0].name == 'b' && out[0].providers.len == 2
	assert out[1].name == 'a'
}

fn test_filters() {
	es := [mk('tsc', 'npm', '/a', 1), mk('git', 'brew', '/b', 2), mk('jupyter', 'conda', '/c', 3)]
	mut m := es.clone()
	m[2].scope = 'miniforge3/envs/ml'
	m[2].description = 'Notebook'
	assert filter_by_source(es, 'brew').len == 1
	assert filter_by_source(es, '').len == 3
	assert filter_by_scope(m, 'miniforge3/envs/ml').len == 1
	assert filter_by_scope(m, '').len == 3
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
