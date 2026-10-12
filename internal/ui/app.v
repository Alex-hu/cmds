module ui

import internal.model
import term

// AppState 维护 TUI 交互运行期间的全部三级界面状态。
pub struct AppState {
pub mut:
	all_entries []model.Entry
	// Level 1: 生态 (Ecosystem)
	ecosystems     []string
	active_eco_idx int
	eco_offset     int
	eco_counts     map[string]int
	// Level 2: 包/环境管理器 (Manager)
	managers       []string
	active_mgr_idx int
	mgr_offset     int
	mgr_counts     map[string]int
	// Level 3: 环境与版本 (Scope)
	scopes           []string
	active_scope_idx int
	scope_offset     int
	scope_counts     map[string]int

	visible_entries []model.Entry
	cursor_idx      int
	page_size       int
	filter_text     string
	searching       bool
	show_detail     bool
}

// new_app_state 初始化交互状态。
pub fn new_app_state(entries []model.Entry) AppState {
	candidate_ecos := ['all', 'node', 'python', 'go', 'rust', 'brew', 'system', 'app', 'manual',
		'ruby']
	mut state := AppState{
		all_entries: entries
		page_size:   15
	}
	state.compute_eco_counts()

	// 过滤顶层生态 Tab：除 'all' 外，仅保留命令数量 > 0 的生态
	mut active_ecos := []string{}
	for e in candidate_ecos {
		if e == 'all' {
			active_ecos << e
		} else if (state.eco_counts[e] or { 0 }) > 0 {
			active_ecos << e
		}
	}
	for entry in entries {
		if entry.ecosystem !in candidate_ecos && entry.ecosystem !in active_ecos
			&& (state.eco_counts[entry.ecosystem] or { 0 }) > 0 {
			active_ecos << entry.ecosystem
		}
	}
	if active_ecos.len == 0 {
		active_ecos << 'all'
	}
	state.ecosystems = active_ecos

	state.refresh_managers()
	state.refresh_scopes()
	state.apply_filter()
	return state
}

// compute_eco_counts 计算一级生态分类的总数。
fn (mut s AppState) compute_eco_counts() {
	s.eco_counts['all'] = s.all_entries.len
	for e in s.all_entries {
		s.eco_counts[e.ecosystem] = (s.eco_counts[e.ecosystem] or { 0 }) + 1
	}
}

// show_manager_row 判断是否展示二级包管理器 Tab 行（当当前生态下有 >= 2 个管理器时展开）。
pub fn (s AppState) show_manager_row() bool {
	cur_eco := s.ecosystems[s.active_eco_idx]
	if cur_eco == 'all' {
		return false
	}
	return s.managers.len > 2
}

// show_scope_row 判断是否展示三级环境/版本 Tab 行（当当前选定管理器下有 >= 2 个具体环境时展开）。
pub fn (s AppState) show_scope_row() bool {
	cur_eco := s.ecosystems[s.active_eco_idx]
	if cur_eco == 'all' {
		return false
	}
	return s.scopes.len > 2
}

// fixed_overhead 动态计算非数据表格区域所占用的总行高。
pub fn (s AppState) fixed_overhead() int {
	mut h := 8 // 标题(1) + 一级生态(1) + 搜索(1) + 表格顶(1) + 表头(1) + 表格中(1) + 表格底(1) + 底栏(1)
	if s.show_manager_row() {
		h++
	}
	if s.show_scope_row() {
		h++
	}
	return h
}

// refresh_managers 当一级生态变化时，提取二级包/环境管理器列表。
fn (mut s AppState) refresh_managers() {
	cur_eco := s.ecosystems[s.active_eco_idx]
	s.active_mgr_idx = 0
	s.mgr_offset = 0
	s.managers = []
	s.mgr_counts = map[string]int{}

	if cur_eco == 'all' {
		return
	}

	mut seen := map[string]bool{}
	mut distinct_managers := []string{}
	mut total_in_eco := 0

	for e in s.all_entries {
		if e.ecosystem != cur_eco {
			continue
		}
		total_in_eco++
		mgr_name := if e.manager.len > 0 { e.manager } else { cur_eco }
		if !seen[mgr_name] {
			seen[mgr_name] = true
			distinct_managers << mgr_name
		}
		s.mgr_counts[mgr_name] = (s.mgr_counts[mgr_name] or { 0 }) + 1
	}

	if distinct_managers.len > 1 {
		s.managers << 'all'
		s.mgr_counts['all'] = total_in_eco
		for m in distinct_managers {
			s.managers << m
		}
	} else if distinct_managers.len == 1 {
		s.managers << distinct_managers[0]
		s.mgr_counts[distinct_managers[0]] = total_in_eco
	}
}

// refresh_scopes 当一级生态或二级管理器变化时，提取三级环境/版本列表。
fn (mut s AppState) refresh_scopes() {
	cur_eco := s.ecosystems[s.active_eco_idx]
	s.active_scope_idx = 0
	s.scope_offset = 0
	s.scopes = []
	s.scope_counts = map[string]int{}

	if cur_eco == 'all' {
		return
	}

	cur_mgr := if s.show_manager_row() && s.active_mgr_idx < s.managers.len {
		s.managers[s.active_mgr_idx]
	} else {
		'all'
	}

	mut seen := map[string]bool{}
	mut distinct_scopes := []string{}
	mut total_matching := 0

	for e in s.all_entries {
		if e.ecosystem != cur_eco {
			continue
		}
		if cur_mgr != 'all' && e.manager != cur_mgr {
			continue
		}
		total_matching++
		if e.scope.len > 0 {
			if !seen[e.scope] {
				seen[e.scope] = true
				distinct_scopes << e.scope
			}
			s.scope_counts[e.scope] = (s.scope_counts[e.scope] or { 0 }) + 1
		}
	}

	if distinct_scopes.len > 1 {
		s.scopes << 'all'
		s.scope_counts['all'] = total_matching
		for sc in distinct_scopes {
			s.scopes << sc
		}
	} else if distinct_scopes.len == 1 {
		s.scopes << distinct_scopes[0]
		s.scope_counts[distinct_scopes[0]] = total_matching
	}
}

// apply_filter 根据当前选中的生态、包管理器、环境/版本与搜索词筛选出可见命令列表。
fn (mut s AppState) apply_filter() {
	cur_eco := s.ecosystems[s.active_eco_idx]
	mut filtered := if cur_eco == 'all' {
		s.all_entries.clone()
	} else {
		s.all_entries.filter(it.ecosystem == cur_eco)
	}

	// 二级包管理器过滤
	if s.show_manager_row() && s.active_mgr_idx < s.managers.len {
		active_mgr := s.managers[s.active_mgr_idx]
		if active_mgr != 'all' {
			filtered = filtered.filter(it.manager == active_mgr)
		}
	}

	// 三级环境/版本过滤
	if s.show_scope_row() && s.active_scope_idx < s.scopes.len {
		active_sc := s.scopes[s.active_scope_idx]
		if active_sc != 'all' {
			filtered = filtered.filter(it.scope == active_sc)
		}
	}

	// 搜索文本过滤
	if s.filter_text.len > 0 {
		q := s.filter_text.to_lower()
		filtered = filtered.filter(it.name.to_lower().contains(q)
			|| it.description.to_lower().contains(q)
			|| it.origin.to_lower().contains(q)
			|| it.scope.to_lower().contains(q)
			|| it.ecosystem.to_lower().contains(q)
			|| it.manager.to_lower().contains(q))
	}

	s.visible_entries = filtered
	if s.visible_entries.len == 0 {
		s.cursor_idx = 0
	} else if s.cursor_idx >= s.visible_entries.len {
		s.cursor_idx = s.visible_entries.len - 1
	} else if s.cursor_idx < 0 {
		s.cursor_idx = 0
	}
}

// total_pages 计算当前筛选结果的总页数。
pub fn (s AppState) total_pages() int {
	if s.visible_entries.len == 0 {
		return 1
	}
	ps := if s.page_size > 0 { s.page_size } else { 1 }
	return (s.visible_entries.len + ps - 1) / ps
}

// current_page 计算当前光标所在的页码（0-indexed）。
pub fn (s AppState) current_page() int {
	ps := if s.page_size > 0 { s.page_size } else { 1 }
	return s.cursor_idx / ps
}

// page_start 返回当前页第一条数据在 visible_entries 中的下标。
pub fn (s AppState) page_start() int {
	return s.current_page() * s.page_size
}

// page_end 返回当前页最后一条数据在 visible_entries 中的结束下标（开区间）。
pub fn (s AppState) page_end() int {
	end := s.page_start() + s.page_size
	if end > s.visible_entries.len {
		return s.visible_entries.len
	}
	return end
}

// next_page 翻到下一页（光标定在下一页首项）。
pub fn (mut s AppState) next_page() {
	if s.visible_entries.len == 0 {
		return
	}
	tot := s.total_pages()
	cur := s.current_page()
	if cur + 1 < tot {
		s.cursor_idx = (cur + 1) * s.page_size
	} else {
		s.cursor_idx = s.visible_entries.len - 1
	}
}

// prev_page 翻到上一页（光标定在上一页首项）。
pub fn (mut s AppState) prev_page() {
	if s.visible_entries.len == 0 {
		return
	}
	cur := s.current_page()
	if cur > 0 {
		s.cursor_idx = (cur - 1) * s.page_size
	} else {
		s.cursor_idx = 0
	}
}

// move_down 光标向下移动一行，跨越页尾时自动进入下一页。
pub fn (mut s AppState) move_down() {
	if s.cursor_idx + 1 < s.visible_entries.len {
		s.cursor_idx++
	}
}

// move_up 光标向上移动一行，跨越页首时自动进入上一页。
pub fn (mut s AppState) move_up() {
	if s.cursor_idx > 0 {
		s.cursor_idx--
	}
}

// next_eco 切换到下一个一级生态 Tab，重置光标为第 1 页。
pub fn (mut s AppState) next_eco() {
	s.active_eco_idx = (s.active_eco_idx + 1) % s.ecosystems.len
	s.refresh_managers()
	s.refresh_scopes()
	s.cursor_idx = 0
	s.apply_filter()
}

// prev_eco 切换到上一个一级生态 Tab，重置光标为第 1 页。
pub fn (mut s AppState) prev_eco() {
	s.active_eco_idx = if s.active_eco_idx == 0 {
		s.ecosystems.len - 1
	} else {
		s.active_eco_idx - 1
	}
	s.refresh_managers()
	s.refresh_scopes()
	s.cursor_idx = 0
	s.apply_filter()
}

// next_manager 切换到下一个二级包管理器 Tab。
pub fn (mut s AppState) next_manager() {
	if s.show_manager_row() && s.managers.len > 1 {
		s.active_mgr_idx = (s.active_mgr_idx + 1) % s.managers.len
		s.refresh_scopes()
		s.cursor_idx = 0
		s.apply_filter()
	}
}

// prev_manager 切换到上一个二级包管理器 Tab。
pub fn (mut s AppState) prev_manager() {
	if s.show_manager_row() && s.managers.len > 1 {
		s.active_mgr_idx = if s.active_mgr_idx == 0 {
			s.managers.len - 1
		} else {
			s.active_mgr_idx - 1
		}
		s.refresh_scopes()
		s.cursor_idx = 0
		s.apply_filter()
	}
}

// next_scope 切换到下一个三级环境/版本 Tab。
pub fn (mut s AppState) next_scope() {
	if s.show_scope_row() && s.scopes.len > 1 {
		s.active_scope_idx = (s.active_scope_idx + 1) % s.scopes.len
		s.cursor_idx = 0
		s.apply_filter()
	}
}

// prev_scope 切换到上一个三级环境/版本 Tab。
pub fn (mut s AppState) prev_scope() {
	if s.show_scope_row() && s.scopes.len > 1 {
		s.active_scope_idx = if s.active_scope_idx == 0 {
			s.scopes.len - 1
		} else {
			s.active_scope_idx - 1
		}
		s.cursor_idx = 0
		s.apply_filter()
	}
}

// next_tab 兼容别名，切换到下一个一级生态。
pub fn (mut s AppState) next_tab() {
	s.next_eco()
}

// prev_tab 兼容别名，切换到上一个一级生态。
pub fn (mut s AppState) prev_tab() {
	s.prev_eco()
}

// next_subtab 兼容别名，切换到下一个三级环境。
pub fn (mut s AppState) next_subtab() {
	s.next_scope()
}

// prev_subtab 兼容别名，切换到上一个三级环境。
pub fn (mut s AppState) prev_subtab() {
	s.prev_scope()
}

// adjust_tab_offsets 依据终端宽度 cols 调整一级生态、二级管理器与三级环境的横向滚动视口，确保激活项始终可见。
pub fn (mut s AppState) adjust_tab_offsets(cols int) {
	// 1. 一级生态视口
	mut eco_widths := []int{}
	for idx, eco in s.ecosystems {
		count := s.eco_counts[eco] or { 0 }
		label := '${ecosystem_display_name(eco)} ${count}'
		pill := if idx == s.active_eco_idx {
			'${bg_tab_on}${fg_white}${ansi_bold} [ ${label} ] ${ansi_reset} '
		} else {
			'${fg_gray} ${label}  ${ansi_reset}'
		}
		eco_widths << term.printable_len(pill)
	}
	s.eco_offset = compute_scroll_offset(s.ecosystems.len,
		s.active_eco_idx,
		s.eco_offset,
		cols,
		1,
		fn [eco_widths] (idx int) int {
			return eco_widths[idx]
		})

	// 2. 二级包管理器视口
	if s.show_manager_row() {
		prefix_str := ' 管理器：'
		prefix_w := term.printable_len(prefix_str)
		mut mgr_widths := []int{}
		for idx, mgr in s.managers {
			count := s.mgr_counts[mgr] or { 0 }
			disp := manager_display_name(mgr)
			label := '${disp} · ${count}'
			pill := if idx == s.active_mgr_idx {
				'${bg_tab_on}${fg_white}${ansi_bold} [ ${label} ] ${ansi_reset} '
			} else {
				'${fg_gray} ${label}  ${ansi_reset}'
			}
			mgr_widths << term.printable_len(pill)
		}
		s.mgr_offset = compute_scroll_offset(s.managers.len,
			s.active_mgr_idx,
			s.mgr_offset,
			cols,
			prefix_w,
			fn [mgr_widths] (idx int) int {
				return mgr_widths[idx]
			})
	} else {
		s.mgr_offset = 0
	}

	// 3. 三级环境/版本视口
	if s.show_scope_row() {
		cur_eco := s.ecosystems[s.active_eco_idx]
		prefix_str := if cur_eco == 'python' {
			' 环境：'
		} else if cur_eco == 'node' {
			' 版本：'
		} else if cur_eco == 'go' {
			' 范围：'
		} else {
			' 环境/版本：'
		}
		prefix_w := term.printable_len(prefix_str)
		mut sc_widths := []int{}
		for idx, sc in s.scopes {
			count := s.scope_counts[sc] or { 0 }
			disp := subtab_display_name(cur_eco, sc)
			label := '${disp} · ${count}'
			pill := if idx == s.active_scope_idx {
				'${bg_pill_on}${fg_white}${ansi_bold} (${label}) ${ansi_reset} '
			} else {
				'${fg_gray} ${label}  ${ansi_reset}'
			}
			sc_widths << term.printable_len(pill)
		}
		s.scope_offset = compute_scroll_offset(s.scopes.len,
			s.active_scope_idx,
			s.scope_offset,
			cols,
			prefix_w,
			fn [sc_widths] (idx int) int {
				return sc_widths[idx]
			})
	} else {
		s.scope_offset = 0
	}
}

// run 启动交互式 TUI 浏览器主循环。
pub fn run(entries []model.Entry) ! {
	if entries.len == 0 {
		println('(无已索引命令，请先运行 cmds update)')
		return
	}

	mut guard := TerminalRawGuard{}
	guard.enable()!
	defer {
		guard.disable()
	}

	mut state := new_app_state(entries)
	mut last_cols := 0
	mut last_rows := 0

	for {
		cols, rows := term.get_terminal_size()
		if cols != last_cols || rows != last_rows {
			last_cols = cols
			last_rows = rows
			print('\x1b[2J') // 终端大小变化时先全屏清理残留
		}

		// 根据屏幕高度与当前显示的 Tab 行动态计算单屏展示行数 (page_size)
		overhead := state.fixed_overhead()
		state.page_size = if rows > overhead + 2 { rows - overhead } else { 1 }

		// 动态调整一级、二级与三级 Tab 滚动视口，确保当前高亮的项始终在可视区域内
		state.adjust_tab_offsets(cols)

		if state.visible_entries.len > 0 && state.cursor_idx >= state.visible_entries.len {
			state.cursor_idx = state.visible_entries.len - 1
		}

		// 渲染当前视口视图
		view_str := render_view(mut state, cols, rows)
		print(view_str)
		flush_stdout()

		// 阻塞等待用户按键
		action := read_key()

		if state.show_detail {
			// 处于详情弹窗时，按任意键或 Enter/Esc/q 关闭
			match action.typ {
				.enter, .escape, .quit {
					state.show_detail = false
				}
				.char {
					if action.ch in [`q`, `Q`] {
						state.show_detail = false
					}
				}
				else {}
			}
			continue
		}

		if state.searching {
			// 搜索输入状态
			match action.typ {
				.enter, .escape {
					state.searching = false
				}
				.backspace {
					if state.filter_text.len > 0 {
						runes := state.filter_text.runes()
						state.filter_text = runes[..runes.len - 1].string()
						state.cursor_idx = 0
						state.apply_filter()
					}
				}
				.char {
					state.filter_text += action.ch.str()
					state.cursor_idx = 0
					state.apply_filter()
				}
				else {}
			}
			continue
		}

		// 正常浏览模式
		match action.typ {
			.quit {
				break
			}
			.tab {
				state.next_eco()
			}
			.shift_tab {
				state.prev_eco()
			}
			.right {
				state.next_scope()
			}
			.left {
				state.prev_scope()
			}
			.up {
				state.move_up()
			}
			.down {
				state.move_down()
			}
			.page_down {
				state.next_page()
			}
			.page_up {
				state.prev_page()
			}
			.home {
				state.cursor_idx = 0
			}
			.end {
				if state.visible_entries.len > 0 {
					state.cursor_idx = state.visible_entries.len - 1
				}
			}
			.enter {
				if state.visible_entries.len > 0 {
					state.show_detail = true
				}
			}
			.escape {
				if state.filter_text.len > 0 {
					state.filter_text = ''
					state.cursor_idx = 0
					state.apply_filter()
				}
			}
			.char {
				match action.ch {
					`q`, `Q` {
						break
					}
					`/` {
						state.searching = true
					}
					`[` {
						state.prev_manager()
					}
					`]` {
						state.next_manager()
					}
					`j` {
						state.move_down()
					}
					`k` {
						state.move_up()
					}
					`h` {
						state.prev_scope()
					}
					`l` {
						state.next_scope()
					}
					`n`, `>`, ` ` {
						state.next_page()
					}
					`p`, `<` {
						state.prev_page()
					}
					`g` {
						state.cursor_idx = 0
					}
					`G` {
						if state.visible_entries.len > 0 {
							state.cursor_idx = state.visible_entries.len - 1
						}
					}
					else {}
				}
			}
			else {}
		}
	}
}
