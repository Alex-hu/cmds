module ui

import internal.model
import term

fn mock_entries() []model.Entry {
	return [
		model.Entry{
			name:         'zsh'
			ecosystem:    'system'
			manager:      'system'
			source_id:    'system'
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
			ecosystem:    'brew'
			manager:      'brew'
			source_id:    'brew'
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
			ecosystem:    'node'
			manager:      'fnm'
			source_id:    'npm'
			origin:       'npm@fnm/v22.12.0'
			scope:        'v22.12.0'
			realpath:     '/n/tsc'
			in_path:      true
			version:      '5.7.2'
			description:  'TypeScript compiler'
			installed_at: '2025-03-01 12:00'
		},
		model.Entry{
			name:         'corepack'
			ecosystem:    'node'
			manager:      'fnm'
			source_id:    'npm'
			origin:       'npm@fnm/v24.11.1'
			scope:        'v24.11.1'
			realpath:     '/n/corepack'
			in_path:      true
			version:      '0.30.0'
			description:  'Corepack'
			installed_at: '2025-03-02 12:00'
		},
		model.Entry{
			name:         'pnpm-cli'
			ecosystem:    'node'
			manager:      'pnpm'
			source_id:    'pnpm'
			origin:       'pnpm:global'
			scope:        ''
			realpath:     '/p/pnpm-cli'
			in_path:      true
			version:      '9.0.0'
			description:  'Pnpm global cli'
			installed_at: '2025-03-03 12:00'
		},
		model.Entry{
			name:         'jupyter'
			ecosystem:    'python'
			manager:      'miniforge3'
			source_id:    'conda'
			origin:       'miniforge3:ml'
			scope:        'ml'
			realpath:     '/c/jupyter'
			in_path:      false
			version:      '1.1.1'
			description:  'Jupyter Notebook'
			installed_at: '2025-04-01 14:00'
		},
		model.Entry{
			name:         'python'
			ecosystem:    'python'
			manager:      'anaconda3'
			source_id:    'conda'
			origin:       'anaconda3:base'
			scope:        'base'
			realpath:     '/c/python'
			in_path:      true
			version:      '3.11.5'
			description:  'Python interpreter'
			installed_at: '2025-04-01 14:00'
		},
		model.Entry{
			name:         'pytest'
			ecosystem:    'python'
			manager:      'anaconda3'
			source_id:    'conda'
			origin:       'anaconda3:myenv'
			scope:        'myenv'
			realpath:     '/c/pytest'
			in_path:      true
			version:      '8.0.0'
			description:  'Python testing tool'
			installed_at: '2025-04-01 14:00'
		},
		model.Entry{
			name:         'kimi'
			ecosystem:    'python'
			manager:      'uv'
			source_id:    'uv'
			origin:       'uv:tool/kimi-cli'
			scope:        'tools'
			realpath:     '/u/kimi'
			in_path:      true
			version:      '0.58'
			description:  'Kimi CLI'
			installed_at: '2025-04-02 14:00'
		},
		model.Entry{
			name:         'go'
			ecosystem:    'go'
			manager:      'go'
			source_id:    'go'
			origin:       'go:toolchain'
			scope:        'toolchain'
			realpath:     '/go/bin/go'
			in_path:      true
			version:      '1.23.0'
			description:  'Go compiler'
			installed_at: '2025-05-01 10:00'
		},
		model.Entry{
			name:         'gofmt'
			ecosystem:    'go'
			manager:      'go'
			source_id:    'go'
			origin:       'go:gopath'
			scope:        'gopath'
			realpath:     '/go/bin/gofmt'
			in_path:      true
			version:      '1.23.0'
			description:  'Go format tool'
			installed_at: '2025-05-01 10:00'
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

fn test_format_source_label() {
	assert format_source_label('node', 'fnm') == 'node/fnm'
	assert format_source_label('node', 'pnpm') == 'node/pnpm'
	assert format_source_label('python', 'anaconda3') == 'anaconda3'
	assert format_source_label('python', 'miniforge3') == 'miniforge3'
	assert format_source_label('python', 'uv') == 'uv'
	assert format_source_label('go', 'go') == 'go'
	assert format_source_label('brew', 'brew') == 'brew'
	assert format_source_label('system', 'system') == 'system'
}

fn test_render_static_table() {
	entries := mock_entries()
	table_str := render_static_table(entries)
	assert table_str.contains('╭')
	assert table_str.contains('╯')
	assert table_str.contains('NAME')
	assert table_str.contains('zsh')
	assert table_str.contains('jupyter')
	assert table_str.contains('node/fnm')
	assert table_str.contains('anaconda3')
	assert table_str.contains('miniforge3')
}

fn test_app_state_3level_tabs() {
	entries := mock_entries()
	mut st := new_app_state(entries)

	// 初始状态：验证 0 个命令的一级生态被过滤，保留拥有条目的生态
	assert st.ecosystems[st.active_eco_idx] == 'all'
	assert st.ecosystems == ['all', 'node', 'python', 'go', 'brew', 'system']
	assert 'rust' !in st.ecosystems
	assert 'app' !in st.ecosystems
	assert 'manual' !in st.ecosystems
	assert st.visible_entries.len == 11
	assert st.eco_counts['all'] == 11
	assert st.eco_counts['node'] == 3
	assert st.eco_counts['python'] == 4
	assert st.eco_counts['go'] == 2

	// 在 'all' 下，二级与三级均折叠
	assert !st.show_manager_row()
	assert !st.show_scope_row()
	assert st.fixed_overhead() == 8

	// 1. 切换到 node 生态 (拥有 2 个管理器: fnm 与 pnpm)
	node_idx := st.ecosystems.index('node')
	st.active_eco_idx = node_idx
	st.refresh_managers()
	st.refresh_scopes()
	st.apply_filter()

	assert st.show_manager_row() // node 有 fnm 和 pnpm，展示二级
	assert st.managers == ['all', 'fnm', 'pnpm']
	assert st.show_scope_row() // fnm 下有 v22.12.0 与 v24.11.1 两个版本，展示三级
	assert st.scopes == ['all', 'v22.12.0', 'v24.11.1']
	assert st.fixed_overhead() == 10 // 满级状态，占用 10 行
	assert st.visible_entries.len == 3

	// 切换 manager 到 pnpm (无三级版本)
	pnpm_idx := st.managers.index('pnpm')
	st.active_mgr_idx = pnpm_idx
	st.refresh_scopes()
	st.apply_filter()

	assert st.show_manager_row()
	assert !st.show_scope_row() // pnpm 无三级环境，自动折叠三级
	assert st.fixed_overhead() == 9 // 折叠 1 行，overhead 降为 9
	assert st.visible_entries.len == 1
	assert st.visible_entries[0].name == 'pnpm-cli'

	// 2. 切换到 python 生态 (拥有 3 个管理器: miniforge3, anaconda3, uv)
	py_idx := st.ecosystems.index('python')
	st.active_eco_idx = py_idx
	st.refresh_managers()
	st.refresh_scopes()
	st.apply_filter()

	assert st.show_manager_row() // python 有多个管理器，二级展示
	assert st.managers == ['all', 'miniforge3', 'anaconda3', 'uv']
	assert st.visible_entries.len == 4

	// 切换管理器到 anaconda3 (包含 base 与 myenv 两个环境)
	ana_idx := st.managers.index('anaconda3')
	st.active_mgr_idx = ana_idx
	st.refresh_scopes()
	st.apply_filter()

	assert st.show_scope_row() // anaconda3 下有 base 与 myenv，三级展示
	assert st.scopes == ['all', 'base', 'myenv']
	assert st.fixed_overhead() == 10
	assert st.visible_entries.len == 2

	// 切换三级环境到 myenv
	myenv_idx := st.scopes.index('myenv')
	st.active_scope_idx = myenv_idx
	st.apply_filter()
	assert st.visible_entries.len == 1
	assert st.visible_entries[0].name == 'pytest'

	// 切换管理器到 uv (单 scope: tools)
	uv_idx := st.managers.index('uv')
	st.active_mgr_idx = uv_idx
	st.refresh_scopes()
	st.apply_filter()

	assert !st.show_scope_row() // 仅 tools 1 个环境，三级折叠
	assert st.fixed_overhead() == 9
	assert st.visible_entries.len == 1
	assert st.visible_entries[0].name == 'kimi'

	// 3. 切换到 go 生态 (单管理器 go，有 toolchain 与 gopath 两个范围)
	go_idx := st.ecosystems.index('go')
	st.active_eco_idx = go_idx
	st.refresh_managers()
	st.refresh_scopes()
	st.apply_filter()

	assert !st.show_manager_row() // go 单管理器折叠
	assert st.show_scope_row() // toolchain / gopath 两个 scope 展开
	assert st.fixed_overhead() == 9
	assert st.scopes == ['all', 'toolchain', 'gopath']
	assert st.visible_entries.len == 2

	// 4. 切换到 system 生态 (单管理器 system，无子环境)
	sys_idx := st.ecosystems.index('system')
	st.active_eco_idx = sys_idx
	st.refresh_managers()
	st.refresh_scopes()
	st.apply_filter()

	assert !st.show_manager_row() // 二级折叠
	assert !st.show_scope_row() // 三级折叠
	assert st.fixed_overhead() == 8 // 扁平状态，overhead 降为 8 (返还 2 行给表格)
	assert st.visible_entries.len == 1
}

fn test_app_state_search_filter() {
	entries := mock_entries()
	mut st := new_app_state(entries)

	// 搜索 'compiler'
	st.filter_text = 'compiler'
	st.apply_filter()
	assert st.visible_entries.len == 2 // tsc 和 go

	// 搜索管理器 'pnpm'
	st.filter_text = 'pnpm'
	st.apply_filter()
	assert st.visible_entries.len == 1
	assert st.visible_entries[0].name == 'pnpm-cli'

	// 清空搜索
	st.filter_text = ''
	st.apply_filter()
	assert st.visible_entries.len == 11
}

fn test_pagination_and_navigation() {
	entries := mock_entries() // 11 entries
	mut st := new_app_state(entries)
	st.page_size = 4 // 每页 4 条，总共 11 条应当有 3 页

	assert st.total_pages() == 3
	assert st.current_page() == 0
	assert st.page_start() == 0
	assert st.page_end() == 4

	// 翻到下一页 (Page 2, index 4..8)
	st.next_page()
	assert st.current_page() == 1
	assert st.cursor_idx == 4
	assert st.page_start() == 4
	assert st.page_end() == 8

	// 再翻到下一页 (Page 3, index 8..11)
	st.next_page()
	assert st.current_page() == 2
	assert st.cursor_idx == 8
	assert st.page_start() == 8
	assert st.page_end() == 11

	// 已经在最后一页，再次 next_page 不越界
	st.next_page()
	assert st.current_page() == 2
	assert st.cursor_idx == 10

	// 翻回上一页 (Page 2)
	st.prev_page()
	assert st.current_page() == 1
	assert st.cursor_idx == 4

	// 单行移动跨页
	st.move_up()
	assert st.cursor_idx == 3
	assert st.current_page() == 0
}

fn test_render_view_no_trailing_newline_and_fixed_header() {
	entries := mock_entries()
	mut st := new_app_state(entries)
	cols := 100
	rows := 24
	st.page_size = rows - st.fixed_overhead()

	view := render_view(mut st, cols, rows)
	// 验证光标从 (1,1) 开始
	assert view.starts_with('\x1b[H')
	// 验证末尾没有多余换行符（防止末行换行触发终端向下滚屏）
	assert !view.ends_with('\n')
	assert !view.ends_with('\r')
	// 验证包含头部 Banner 与生态元素
	assert view.contains('cmds · 命令行工具索引与查询')
	assert view.contains('All')
	assert view.contains('Node')
	assert view.contains('Python')
	// 验证包含底部分页信息
	assert view.contains('第 1/1 页')
}

fn test_subtab_display_name() {
	assert subtab_display_name('conda', 'all') == '所有环境'
	assert subtab_display_name('python', 'all') == '所有环境'
	assert subtab_display_name('node', 'all') == '所有版本'
	assert subtab_display_name('go', 'toolchain') == '工具链'
	assert subtab_display_name('go', 'gopath') == 'GOPATH'
	assert subtab_display_name('conda', 'anaconda3/envs/myenv') == 'anaconda3/myenv'
	assert subtab_display_name('conda', 'anaconda3/base') == 'anaconda3/base'
}

fn test_pad_line_to_cols() {
	ansi_str := '\x1b[38;5;75mhello\x1b[0m'
	padded := pad_line_to_cols(ansi_str, 10)
	assert term.printable_len(padded) == 10
	assert padded.ends_with('     ')

	no_pad := pad_line_to_cols(ansi_str, 5)
	assert term.printable_len(no_pad) == 5
}

fn test_build_scrollable_tabs() {
	pills := ['[ A ]', 'B', 'C', 'D', 'E', 'F', 'G']
	widths := [5, 1, 1, 1, 1, 1, 1]
	cols := 8
	prefix := ''

	line0, off0 := build_scrollable_tabs(pills, widths, 0, 0, cols, prefix, false)
	assert off0 == 0
	assert term.printable_len(line0) <= cols
	assert line0.contains('▶')
	assert !line0.contains('◀')

	line6, off6 := build_scrollable_tabs(pills, widths, 6, 0, cols, prefix, false)
	assert off6 > 0
	assert term.printable_len(line6) <= cols
	assert line6.contains('◀')
	assert !line6.contains('▶')
}

fn test_compute_scroll_offset() {
	get_w := fn (_ int) int {
		return 20
	}

	off0 := compute_scroll_offset(5, 0, 0, 50, 5, get_w)
	assert off0 == 0

	off1 := compute_scroll_offset(5, 1, 0, 50, 5, get_w)
	assert off1 == 0

	off3 := compute_scroll_offset(5, 3, 0, 50, 5, get_w)
	assert off3 >= 2
	assert off3 <= 3

	off_back := compute_scroll_offset(5, 1, off3, 50, 5, get_w)
	assert off_back <= 1
}

fn test_subtab_horizontal_scrolling_in_view() {
	mut entries := []model.Entry{}
	envs := ['base', 'myenv', 'omni', 'py312', 'py39', 'torch']
	for e in envs {
		entries << model.Entry{
			name:         'cmd_' + e
			ecosystem:    'python'
			manager:      'conda'
			source_id:    'conda'
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
	py_idx := st.ecosystems.index('python')
	st.active_eco_idx = py_idx
	st.refresh_managers()
	st.refresh_scopes()
	st.apply_filter()

	// 切换到最后一个环境 (torch)
	st.active_scope_idx = st.scopes.len - 1
	cols := 75 // 较窄的屏幕
	rows := 24
	st.adjust_tab_offsets(cols)

	view := render_view(mut st, cols, rows)
	assert view.contains('◀')
	assert view.contains('torch')
}
