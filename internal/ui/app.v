module ui

import internal.model
import term

// AppState 维护 TUI 交互运行期间的全部界面状态。
pub struct AppState {
pub mut:
	all_entries       []model.Entry
	tabs              []string
	active_tab_idx    int
	subtabs           []string
	active_subtab_idx int
	tab_counts        map[string]int
	subtab_counts     map[string]int
	visible_entries   []model.Entry
	cursor_idx        int
	scroll_offset     int
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
	if s.cursor_idx >= s.visible_entries.len {
		s.cursor_idx = if s.visible_entries.len > 0 { s.visible_entries.len - 1 } else { 0 }
	}
	if s.cursor_idx < 0 {
		s.cursor_idx = 0
	}
	s.adjust_scroll(20) // 预设行高，实际在主循环依据 rows 调整
}

// adjust_scroll 保证光标在视口范围内。
fn (mut s AppState) adjust_scroll(table_height int) {
	if s.visible_entries.len == 0 {
		s.scroll_offset = 0
		return
	}
	if s.cursor_idx < s.scroll_offset {
		s.scroll_offset = s.cursor_idx
	}
	if s.cursor_idx >= s.scroll_offset + table_height {
		s.scroll_offset = s.cursor_idx - table_height + 1
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

	for {
		cols, rows := term.get_terminal_size()
		table_height := if rows > 12 { rows - 10 } else { 5 }
		state.adjust_scroll(table_height)

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
						state.scroll_offset = 0
						state.apply_filter()
					}
				}
				.char {
					// 接收可打印字符
					state.filter_text += action.ch.str()
					state.cursor_idx = 0
					state.scroll_offset = 0
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
				state.active_tab_idx = (state.active_tab_idx + 1) % state.tabs.len
				state.refresh_subtabs()
				state.cursor_idx = 0
				state.scroll_offset = 0
				state.apply_filter()
			}
			.shift_tab {
				state.active_tab_idx = if state.active_tab_idx == 0 {
					state.tabs.len - 1
				} else {
					state.active_tab_idx - 1
				}
				state.refresh_subtabs()
				state.cursor_idx = 0
				state.scroll_offset = 0
				state.apply_filter()
			}
			.right {
				if state.subtabs.len > 1 {
					state.active_subtab_idx = (state.active_subtab_idx + 1) % state.subtabs.len
					state.cursor_idx = 0
					state.scroll_offset = 0
					state.apply_filter()
				}
			}
			.left {
				if state.subtabs.len > 1 {
					state.active_subtab_idx = if state.active_subtab_idx == 0 {
						state.subtabs.len - 1
					} else {
						state.active_subtab_idx - 1
					}
					state.cursor_idx = 0
					state.scroll_offset = 0
					state.apply_filter()
				}
			}
			.up {
				if state.cursor_idx > 0 {
					state.cursor_idx--
				}
			}
			.down {
				if state.cursor_idx + 1 < state.visible_entries.len {
					state.cursor_idx++
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
					state.scroll_offset = 0
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
						if state.cursor_idx + 1 < state.visible_entries.len {
							state.cursor_idx++
						}
					}
					`k` {
						if state.cursor_idx > 0 {
							state.cursor_idx--
						}
					}
					`h` {
						if state.subtabs.len > 1 {
							state.active_subtab_idx = if state.active_subtab_idx == 0 {
								state.subtabs.len - 1
							} else {
								state.active_subtab_idx - 1
							}
							state.cursor_idx = 0
							state.scroll_offset = 0
							state.apply_filter()
						}
					}
					`l` {
						if state.subtabs.len > 1 {
							state.active_subtab_idx = (state.active_subtab_idx + 1) % state.subtabs.len
							state.cursor_idx = 0
							state.scroll_offset = 0
							state.apply_filter()
						}
					}
					else {}
				}
			}
			else {}
		}
	}
}
