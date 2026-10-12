module ui

import internal.model

fn mock_entries() []model.Entry {
	return [
		model.Entry{
			name:         'zsh'
			source:       'system'
			origin:       'system'
			scope:        ''
			realpath:     '/bin/zsh'
			in_path:      true
			version:      '5.9'
			description:  'Z shell'
			installed_at: '2025-01-01 00:00'
		},
		model.Entry{
			name:         'git'
			source:       'brew'
			origin:       'brew'
			scope:        ''
			realpath:     '/usr/local/bin/git'
			in_path:      true
			version:      '2.47.1'
			description:  'Git version control'
			installed_at: '2025-02-01 10:00'
		},
		model.Entry{
			name:         'tsc'
			source:       'npm'
			origin:       'npm@fnm/v22.12.0'
			scope:        'fnm/v22.12.0'
			realpath:     '/n/tsc'
			in_path:      true
			version:      '5.7.2'
			description:  'TypeScript compiler'
			installed_at: '2025-03-01 12:00'
		},
		model.Entry{
			name:         'jupyter'
			source:       'conda'
			origin:       'conda:miniforge3/envs/ml'
			scope:        'miniforge3/envs/ml'
			realpath:     '/c/jupyter'
			in_path:      false
			version:      '1.1.1'
			description:  'Jupyter Notebook'
			installed_at: '2025-04-01 14:00'
		},
		model.Entry{
			name:         'python'
			source:       'conda'
			origin:       'conda:anaconda3/base'
			scope:        'anaconda3/base'
			realpath:     '/c/python'
			in_path:      true
			version:      '3.11.5'
			description:  'Python interpreter'
			installed_at: '2025-04-01 14:00'
		},
	]
}

fn test_pad_or_truncate() {
	// 英文填充
	assert pad_or_truncate('abc', 6) == 'abc   '
	// 英文截断
	assert pad_or_truncate('abcdefghij', 5) == 'abcd…'
	// 中文宽度测试（'你好' 可视宽度为 4）
	assert pad_or_truncate('你好', 6) == '你好  '
}

fn test_render_static_table() {
	entries := mock_entries()
	table_str := render_static_table(entries)
	assert table_str.contains('╭')
	assert table_str.contains('╯')
	assert table_str.contains('NAME')
	assert table_str.contains('zsh')
	assert table_str.contains('jupyter')
}

fn test_app_state_tabs_and_subtabs() {
	entries := mock_entries()
	mut st := new_app_state(entries)

	// 初始状态
	assert st.tabs[st.active_tab_idx] == 'all'
	assert st.visible_entries.len == 5
	assert st.tab_counts['all'] == 5
	assert st.tab_counts['conda'] == 2
	assert st.tab_counts['npm'] == 1

	// 切换到 conda 一级 tab（索引为 4）
	st.active_tab_idx = 4
	assert st.tabs[st.active_tab_idx] == 'conda'
	st.refresh_subtabs()
	st.apply_filter()

	// conda 应该有 2 个条目
	assert st.visible_entries.len == 2
	// 应该有二级环境
	assert st.subtabs.len == 3 // all + miniforge3/envs/ml + anaconda3/base
	assert 'all' in st.subtabs
	assert 'miniforge3/envs/ml' in st.subtabs

	// 切换二级 tab 到 miniforge3/envs/ml
	ml_idx := st.subtabs.index('miniforge3/envs/ml')
	assert ml_idx >= 0
	st.active_subtab_idx = ml_idx
	st.apply_filter()

	// 此时只应该看见 jupyter
	assert st.visible_entries.len == 1
	assert st.visible_entries[0].name == 'jupyter'
}

fn test_app_state_search_filter() {
	entries := mock_entries()
	mut st := new_app_state(entries)

	// 搜索 'type'
	st.filter_text = 'type'
	st.apply_filter()
	assert st.visible_entries.len == 1
	assert st.visible_entries[0].name == 'tsc'

	// 清空搜索
	st.filter_text = ''
	st.apply_filter()
	assert st.visible_entries.len == 5
}

fn test_scroll_adjustment() {
	entries := mock_entries()
	mut st := new_app_state(entries)

	st.cursor_idx = 4
	st.adjust_scroll(3)
	// 当可视高度为 3，光标在 4 时，滚动偏移量应当上移到保证光标可见
	assert st.scroll_offset >= 2
	assert st.cursor_idx < st.scroll_offset + 3
}
