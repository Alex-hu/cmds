module ui

import internal.model
import term

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

	// 初始状态：验证 0 个命令的顶层 tab（cargo/go/pnpm/rvm 等）被自动过滤
	assert st.tabs[st.active_tab_idx] == 'all'
	assert st.tabs == ['all', 'system', 'brew', 'npm', 'conda']
	assert 'cargo' !in st.tabs
	assert 'go' !in st.tabs
	assert 'pnpm' !in st.tabs
	assert st.visible_entries.len == 5
	assert st.tab_counts['all'] == 5
	assert st.tab_counts['conda'] == 2
	assert st.tab_counts['npm'] == 1

	// 切换到 conda 一级 tab
	conda_idx := st.tabs.index('conda')
	st.active_tab_idx = conda_idx
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

	view := render_view(mut st, cols, rows)
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

fn test_subtab_display_name() {
	assert subtab_display_name('conda', 'all') == '所有环境'
	assert subtab_display_name('npm', 'all') == '所有版本'
	assert subtab_display_name('conda', 'anaconda3/envs/myenv') == 'anaconda3/myenv'
	assert subtab_display_name('conda', 'anaconda3/base') == 'anaconda3/base'
	assert subtab_display_name('npm', 'fnm/v22.12.0') == 'fnm/v22.12.0'
}

fn test_pad_line_to_cols() {
	ansi_str := '\x1b[38;5;75mhello\x1b[0m'
	padded := pad_line_to_cols(ansi_str, 10)
	// 可视宽度必须正好是 10
	assert term.printable_len(padded) == 10
	assert padded.ends_with('     ')

	// 宽度小于等于自身时保持原样并带 reset
	no_pad := pad_line_to_cols(ansi_str, 5)
	assert term.printable_len(no_pad) == 5
}

fn test_build_scrollable_tabs() {
	pills := ['[ A ]', 'B', 'C', 'D', 'E', 'F', 'G']
	widths := [5, 1, 1, 1, 1, 1, 1]
	cols := 8
	prefix := ''

	// active 为 0，应显示 0..3 并带右指示器 ▶
	line0, off0 := build_scrollable_tabs(pills, widths, 0, 0, cols, prefix, false)
	assert off0 == 0
	assert term.printable_len(line0) <= cols
	assert line0.contains('▶')
	assert !line0.contains('◀')

	// active 为 6（末尾），应推进 offset 并带左指示器 ◀
	line6, off6 := build_scrollable_tabs(pills, widths, 6, 0, cols, prefix, false)
	assert off6 > 0
	assert term.printable_len(line6) <= cols
	assert line6.contains('◀')
	assert !line6.contains('▶')
}

fn test_compute_scroll_offset() {
	// 模拟 5 个 tab，每个宽度 20
	// 屏幕 cols 为 50，前缀宽度为 5
	// 最多同时容纳约 2 个 tab
	get_w := fn (_ int) int {
		return 20
	}

	// 激活第 0 项：offset 应当为 0
	off0 := compute_scroll_offset(5, 0, 0, 50, 5, get_w)
	assert off0 == 0

	// 激活第 1 项：从 0 开始宽 5 + 20 + 20 + 2 = 47 <= 50，依然能容纳，offset 为 0
	off1 := compute_scroll_offset(5, 1, 0, 50, 5, get_w)
	assert off1 == 0

	// 激活第 3 项：从 0 开始塞不下第 3 项，必须向右滚动
	off3 := compute_scroll_offset(5, 3, 0, 50, 5, get_w)
	assert off3 >= 2
	assert off3 <= 3

	// 从 offset 2 回退到第 1 项：offset 必须向左退回到 <= 1
	off_back := compute_scroll_offset(5, 1, off3, 50, 5, get_w)
	assert off_back <= 1
}

fn test_subtab_horizontal_scrolling_in_view() {
	// 构造 6 个 conda 环境的条目
	mut entries := []model.Entry{}
	envs := ['base', 'myenv', 'omni', 'py312', 'py39', 'torch']
	for e in envs {
		entries << model.Entry{
			name:         'cmd_' + e
			source:       'conda'
			origin:       'conda:anaconda3/envs/' + e
			scope:        'anaconda3/envs/' + e
			realpath:     '/bin/' + e
			in_path:      true
			version:      '1.0'
			description:  'test'
			installed_at: '2025-01-01'
		}
	}

	mut st := new_app_state(entries)
	// 切换到 conda tab
	conda_idx := st.tabs.index('conda')
	st.active_tab_idx = conda_idx
	st.refresh_subtabs()
	st.apply_filter()

	// 切换到最后一个环境 (torch)
	st.active_subtab_idx = st.subtabs.len - 1
	cols := 75 // 较窄的屏幕
	rows := 24
	st.adjust_tab_offsets(cols)

	view := render_view(mut st, cols, rows)
	// 验证包含左指示箭头 ◀
	assert view.contains('◀')
	// 验证当前选中的环境名在视口中完整可见且高亮包含在内
	assert view.contains('torch')
}
