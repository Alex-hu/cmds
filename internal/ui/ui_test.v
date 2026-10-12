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

fn test_pagination_and_navigation() {
	entries := mock_entries() // 5 entries
	mut st := new_app_state(entries)
	st.page_size = 2 // 每页 2 条，总共 5 条应当有 3 页

	assert st.total_pages() == 3
	assert st.current_page() == 0
	assert st.page_start() == 0
	assert st.page_end() == 2

	// 翻到下一页 (Page 2, index 2..4)
	st.next_page()
	assert st.current_page() == 1
	assert st.cursor_idx == 2
	assert st.page_start() == 2
	assert st.page_end() == 4

	// 再翻到下一页 (Page 3, index 4..5)
	st.next_page()
	assert st.current_page() == 2
	assert st.cursor_idx == 4
	assert st.page_start() == 4
	assert st.page_end() == 5

	// 已经在最后一页，再次 next_page 不越界
	st.next_page()
	assert st.current_page() == 2
	assert st.cursor_idx == 4

	// 翻回上一页 (Page 2)
	st.prev_page()
	assert st.current_page() == 1
	assert st.cursor_idx == 2

	// 单行向下移动跨页测试：
	// 当前在 index 2，按 down 到 index 3（仍是 Page 2）
	st.move_down()
	assert st.cursor_idx == 3
	assert st.current_page() == 1
	// 再按 down 到 index 4（自动跨入 Page 3）
	st.move_down()
	assert st.cursor_idx == 4
	assert st.current_page() == 2

	// 单行向上移动跨页测试：
	// 从 index 4 按 up 到 index 3（自动退回 Page 2）
	st.move_up()
	assert st.cursor_idx == 3
	assert st.current_page() == 1
}

fn test_render_view_no_trailing_newline_and_fixed_header() {
	entries := mock_entries()
	mut st := new_app_state(entries)
	cols := 100
	rows := 24
	st.page_size = rows - 9 // 15

	view := render_view(st, cols, rows)
	// 验证光标从 (1,1) 开始
	assert view.starts_with('\x1b[H')
	// 验证末尾没有多余换行符（防止末行换行触发终端向下滚屏）
	assert !view.ends_with('\n')
	assert !view.ends_with('\r')
	// 验证包含头部 Banner 与 Tab 元素
	assert view.contains('cmds · 命令行工具索引与查询')
	assert view.contains('All')
	assert view.contains('conda')
	// 验证包含底部分页信息
	assert view.contains('第 1/1 页')
}
