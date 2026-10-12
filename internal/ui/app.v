module ui

import internal.model
import term

// AppState 维护 TUI 交互运行期间的全部界面状态。
pub struct AppState {
pub mut:
	all_entries       []model.Entry
	tabs              []string
	active_tab_idx    int
	tab_offset        int
	subtabs           []string
	active_subtab_idx int
	subtab_offset     int
	tab_counts        map[string]int
	subtab_counts     map[string]int
	visible_entries   []model.Entry
	cursor_idx        int
	page_size         int
	filter_text       string
	searching         bool
	show_detail       bool
}

// new_app_state 初始化交互状态。
pub fn new_app_state(entries []model.Entry) AppState {
	tabs := ['all', 'system', 'brew', 'npm', 'conda', 'cargo', 'go', 'rvm', 'app', 'manual']
	mut state := AppState{
		all_entries: entries
		tabs:        tabs
		page_size:   15
	}
	state.compute_tab_counts()
	state.refresh_subtabs()
	state.apply_filter()
	return state
}

// compute_tab_counts 计算一级分类的总数。
fn (mut s AppState) compute_tab_counts() {
	s.tab_counts['all'] = s.all_entries.len
	for e in s.all_entries {
		s.tab_counts[e.source] = (s.tab_counts[e.source] or { 0 }) + 1
	}
}

// refresh_subtabs 当一级分类变化时，提取二级分类清单。
fn (mut s AppState) refresh_subtabs() {
	cur_tab := s.tabs[s.active_tab_idx]
	s.active_subtab_idx = 0
	s.subtab_offset = 0
	s.subtabs = []
	s.subtab_counts = map[string]int{}

	if cur_tab !in ['conda', 'npm'] {
		return
	}

	mut seen := map[string]bool{}
	mut list := ['all']
	mut total_sub_count := 0

	for e in s.all_entries {
		if e.source != cur_tab {
			continue
		}
		total_sub_count++
		scope_val := if e.scope.len > 0 { e.scope } else { 'default' }
		if !seen[scope_val] {
			seen[scope_val] = true
			list << scope_val
		}
		s.subtab_counts[scope_val] = (s.subtab_counts[scope_val] or { 0 }) + 1
	}
	s.subtab_counts['all'] = total_sub_count
	s.subtabs = list
}

// apply_filter 根据当前选中的一级 Tab、二级 Tab 与搜索词筛选出可见命令列表。
fn (mut s AppState) apply_filter() {
	cur_tab := s.tabs[s.active_tab_idx]
	mut filtered := if cur_tab == 'all' {
		s.all_entries.clone()
	} else {
		s.all_entries.filter(it.source == cur_tab)
	}

	// 二级分类过滤
	if cur_tab in ['conda', 'npm'] && s.subtabs.len > 0 {
		active_sub := s.subtabs[s.active_subtab_idx]
		if active_sub != 'all' {
			filtered = filtered.filter(if it.scope.len > 0 {
				it.scope == active_sub
			} else {
				active_sub == 'default'
			})
		}
	}

	// 搜索文本过滤
	if s.filter_text.len > 0 {
		q := s.filter_text.to_lower()
		filtered = filtered.filter(it.name.to_lower().contains(q)
			|| it.description.to_lower().contains(q)
			|| it.origin.to_lower().contains(q)
			|| it.scope.to_lower().contains(q))
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

// next_tab 切换到下一个一级 Tab，重置光标为第 1 页。
pub fn (mut s AppState) next_tab() {
	s.active_tab_idx = (s.active_tab_idx + 1) % s.tabs.len
	s.refresh_subtabs()
	s.cursor_idx = 0
	s.apply_filter()
}

// prev_tab 切换到上一个一级 Tab，重置光标为第 1 页。
pub fn (mut s AppState) prev_tab() {
	s.active_tab_idx = if s.active_tab_idx == 0 {
		s.tabs.len - 1
	} else {
		s.active_tab_idx - 1
	}
	s.refresh_subtabs()
	s.cursor_idx = 0
	s.apply_filter()
}

// next_subtab 切换到下一个二级 Subtab，重置光标为第 1 页。
pub fn (mut s AppState) next_subtab() {
	if s.subtabs.len > 1 {
		s.active_subtab_idx = (s.active_subtab_idx + 1) % s.subtabs.len
		s.cursor_idx = 0
		s.apply_filter()
	}
}

// prev_subtab 切换到上一个二级 Subtab，重置光标为第 1 页。
pub fn (mut s AppState) prev_subtab() {
	if s.subtabs.len > 1 {
		s.active_subtab_idx = if s.active_subtab_idx == 0 {
			s.subtabs.len - 1
		} else {
			s.active_subtab_idx - 1
		}
		s.cursor_idx = 0
		s.apply_filter()
	}
}

// adjust_tab_offsets 依据终端宽度 cols 调整一级 Tab 与二级 Subtab 的横向滚动视口，确保激活项始终可见。
pub fn (mut s AppState) adjust_tab_offsets(cols int) {
	s.tab_offset = compute_scroll_offset(s.tabs.len,
		s.active_tab_idx,
		s.tab_offset,
		cols,
		1,
		fn [s] (idx int) int {
			t := s.tabs[idx]
			count := s.tab_counts[t] or { 0 }
			label := '${source_display_name(t)} ${count}'
			vis := term.printable_len(label)
			return if idx == s.active_tab_idx { vis + 6 } else { vis + 2 }
		})

	cur_tab := s.tabs[s.active_tab_idx]
	if cur_tab in ['conda', 'npm'] && s.subtabs.len > 0 {
		prefix_str := if cur_tab == 'conda' { ' 环境：' } else { ' node 版本：' }
		prefix_w := term.printable_len(prefix_str)
		s.subtab_offset = compute_scroll_offset(s.subtabs.len,
			s.active_subtab_idx,
			s.subtab_offset,
			cols,
			prefix_w,
			fn [s, cur_tab] (idx int) int {
				sub := s.subtabs[idx]
				count := s.subtab_counts[sub] or { 0 }
				disp_sub := subtab_display_name(cur_tab, sub)
				label := '${disp_sub} · ${count}'
				vis := term.printable_len(label)
				return if idx == s.active_subtab_idx { vis + 4 } else { vis + 2 }
			})
	} else {
		s.subtab_offset = 0
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

		// 根据屏幕高度动态计算单屏展示行数 (page_size)
		// 9 行用于固定的标题栏、两层 Tab、搜索栏、表格边框及表头、底栏
		state.page_size = if rows > 10 { rows - 9 } else { 1 }

		// 动态调整一级与二级 Tab 滚动视口，确保当前高亮的 Tab 始终在可视区域内
		state.adjust_tab_offsets(cols)

		if state.visible_entries.len > 0 && state.cursor_idx >= state.visible_entries.len {
			state.cursor_idx = state.visible_entries.len - 1
		}

		// 渲染当前视口视图
		view_str := render_view(state, cols, rows)
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
				state.next_tab()
			}
			.shift_tab {
				state.prev_tab()
			}
			.right {
				state.next_subtab()
			}
			.left {
				state.prev_subtab()
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
					`j` {
						state.move_down()
					}
					`k` {
						state.move_up()
					}
					`h` {
						state.prev_subtab()
					}
					`l` {
						state.next_subtab()
					}
					`n`, `]`, `>`, ` ` {
						state.next_page()
					}
					`p`, `[`, `<` {
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
