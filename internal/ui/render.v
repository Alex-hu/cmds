module ui

import internal.model
import strings
import term

const ansi_reset = '\x1b[0m'
const ansi_bold = '\x1b[1m'
const fg_white = '\x1b[97m'
const fg_gray = '\x1b[38;5;245m'
const fg_dark = '\x1b[38;5;239m'
const fg_border = '\x1b[38;5;240m'
const fg_accent = '\x1b[38;5;75m'
const fg_yellow = '\x1b[38;5;178m'
const fg_cyan = '\x1b[38;5;73m'
const bg_sel = '\x1b[48;5;236m'
const bg_tab_on = '\x1b[48;5;238m'
const bg_pill_on = '\x1b[48;5;24m'
const bg_modal = '\x1b[48;5;235m'

// render_static_table 渲染无交互的静态 Nushell 风格圆角细线表格。
pub fn render_static_table(entries []model.Entry) string {
	if entries.len == 0 {
		return '(无匹配条目)'
	}
	w_name := 22
	w_src := 8
	w_scope := 22
	w_ver := 10
	w_inst := 17
	w_path := 42

	specs := [
		TableColSpec{ title: 'NAME', width: w_name },
		TableColSpec{ title: 'SOURCE', width: w_src },
		TableColSpec{ title: 'SCOPE', width: w_scope },
		TableColSpec{ title: 'VERSION', width: w_ver },
		TableColSpec{ title: 'INSTALLED', width: w_inst },
		TableColSpec{ title: 'DESCRIPTION / PATH', width: w_path },
	]

	mut sb := strings.new_builder(entries.len * 128)
	sb.write_string(render_nushell_border_top(specs))
	sb.write_string('\n')
	sb.write_string(render_nushell_header(specs))
	sb.write_string('\n')
	sb.write_string(render_nushell_border_mid(specs))
	sb.write_string('\n')

	for e in entries {
		sb.write_string(render_nushell_row(e, specs, false))
		sb.write_string('\n')
	}

	sb.write_string(render_nushell_border_bottom(specs))
	return sb.str()
}

// source_color 为不同来源返回专有 ANSI 前景色（与原型 A2 一致）。
fn source_color(s string) string {
	match s {
		'system' { return '\x1b[38;5;103m' }
		'brew' { return '\x1b[38;5;178m' }
		'npm' { return '\x1b[38;5;71m' }
		'conda' { return '\x1b[38;5;73m' }
		'cargo' { return '\x1b[38;5;173m' }
		'go' { return '\x1b[38;5;75m' }
		'rvm' { return '\x1b[38;5;167m' }
		'app' { return '\x1b[38;5;141m' }
		'manual' { return '\x1b[38;5;244m' }
		else { return fg_gray }
	}
}

// source_display_name 返回来源的友好中文标签。
fn source_display_name(s string) string {
	match s {
		'all' { return 'All' }
		'system' { return '系统' }
		'brew' { return 'brew' }
		'npm' { return 'node/npm' }
		'conda' { return 'conda' }
		'cargo' { return 'cargo' }
		'go' { return 'go' }
		'rvm' { return 'rvm' }
		'app' { return 'app' }
		'manual' { return 'manual' }
		else { return s }
	}
}

// pad_or_truncate 依据终端可视宽度做对齐或截断，确保汉字和英文字符排版不破裂。
pub fn pad_or_truncate(s string, width int) string {
	vis_len := term.printable_len(s)
	if vis_len == width {
		return s
	}
	if vis_len < width {
		return s + ' '.repeat(width - vis_len)
	}
	// 超长截断：逐 rune 累加，直到触达 width - 1 留给 '…'
	runes := s.runes()
	mut sb := strings.new_builder(width * 2)
	mut cur_w := 0
	target_w := if width > 2 { width - 1 } else { width }
	for r in runes {
		rw := term.printable_len(r.str())
		if cur_w + rw > target_w {
			break
		}
		sb.write_rune(r)
		cur_w += rw
	}
	if width > 2 {
		sb.write_string('…')
		cur_w += 1
	}
	if cur_w < width {
		sb.write_string(' '.repeat(width - cur_w))
	}
	return sb.str()
}

// TableColSpec 定义表格单列宽度与标题。
pub struct TableColSpec {
pub:
	title string
	width int
}

// render_view 渲染整个终端视口（Header + Tab栏 + Subtab栏 + Nushell表格 + 状态栏 + 弹窗）。
pub fn render_view(state AppState, cols int, rows int) string {
	// 动态计算单屏展示行数 (page_size)
	// 固定占用 9 行：标题(1) + 一级Tab(1) + 二级Tab(1) + 搜索(1) + 表格顶(1) + 表头(1) + 表格中(1) + 表格底(1) + 底栏(1)
	page_size := if state.page_size > 0 {
		state.page_size
	} else {
		if rows > 10 { rows - 9 } else { 1 }
	}

	// 动态计算各列宽度，确保总宽度不溢出 cols，防止终端折行破坏固定行高
	avail := if cols > 20 { cols - 19 } else { 30 }
	mut w_name := 20
	mut w_src := 10
	mut w_scope := 20
	mut w_ver := 10
	mut w_inst := 17
	if cols < 110 {
		w_name = 18
		w_scope = 16
		w_inst = 15
	}
	if cols < 95 {
		w_name = 15
		w_scope = 12
		w_ver = 8
		w_inst = 12
	}
	if cols < 80 {
		w_name = 14
		w_scope = 10
		w_ver = 7
		w_inst = 10
	}
	fixed_used := w_name + w_src + w_scope + w_ver + w_inst
	w_desc := if avail > fixed_used + 10 { avail - fixed_used } else { 10 }

	specs := [
		TableColSpec{ title: 'NAME', width: w_name },
		TableColSpec{ title: 'SOURCE', width: w_src },
		TableColSpec{ title: 'SCOPE', width: w_scope },
		TableColSpec{ title: 'VERSION', width: w_ver },
		TableColSpec{ title: 'INSTALLED', width: w_inst },
		TableColSpec{ title: 'DESCRIPTION / PATH', width: w_desc },
	]

	mut lines := []string{}

	// 1. 顶部标题栏
	banner := ' cmds · 命令行工具索引与查询 (按来源与环境分类)'
	lines << '${fg_accent}${ansi_bold}${pad_or_truncate(banner, cols)}${ansi_reset}'

	// 2. 一级 Tab 栏
	mut tab_line := strings.new_builder(256)
	tab_line.write_string(' ')
	for i, t in state.tabs {
		count := state.tab_counts[t] or { 0 }
		label := '${source_display_name(t)} ${count}'
		if i == state.active_tab_idx {
			tab_line.write_string('${bg_tab_on}${fg_white}${ansi_bold} [ ${label} ] ${ansi_reset} ')
		} else {
			tab_line.write_string('${fg_gray} ${label} ${ansi_reset} ')
		}
	}
	lines << pad_or_truncate(tab_line.str(), cols)

	// 3. 二级 Tab 栏（Scope）
	cur_tab := state.tabs[state.active_tab_idx]
	mut sub_line := strings.new_builder(256)
	if cur_tab in ['conda', 'npm'] {
		prefix := if cur_tab == 'conda' { ' 环境：' } else { ' node 版本：' }
		sub_line.write_string('${fg_yellow}${prefix}${ansi_reset}')
		for i, s in state.subtabs {
			count := state.subtab_counts[s] or { 0 }
			disp_sub := if s == 'all' {
				if cur_tab == 'conda' { '所有环境' } else { '所有版本' }
			} else {
				s
			}
			label := '${disp_sub} · ${count}'
			if i == state.active_subtab_idx {
				sub_line.write_string('${bg_pill_on}${fg_white}${ansi_bold} (${label}) ${ansi_reset} ')
			} else {
				sub_line.write_string('${fg_gray} ${label} ${ansi_reset} ')
			}
		}
	} else {
		sub_line.write_string(' ${fg_dark}(该来源无二级分类)${ansi_reset}')
	}
	lines << pad_or_truncate(sub_line.str(), cols)

	// 4. 搜索行
	mut search_line := strings.new_builder(128)
	if state.searching {
		search_line.write_string(' ${fg_yellow}${ansi_bold}[/ 搜索] ❯ ${state.filter_text}_${ansi_reset}  ${fg_gray}(按 Enter/Esc 完成)${ansi_reset}')
	} else if state.filter_text.len > 0 {
		search_line.write_string(' ${fg_cyan}[过滤: "${state.filter_text}"]${ansi_reset}  ${fg_gray}(按 / 修改, 按 Esc 清除)${ansi_reset}')
	} else {
		search_line.write_string(' ${fg_dark}提示: 按 / 开启实时搜索过滤${ansi_reset}')
	}
	lines << pad_or_truncate(search_line.str(), cols)

	// 5. Nushell 风格表格顶边、表头与中分线
	lines << render_nushell_border_top(specs)
	lines << render_nushell_header(specs)
	lines << render_nushell_border_mid(specs)

	// 6. 数据行渲染（严格截取当前页条目，并以空行对齐保持总高恒定）
	items := state.visible_entries
	page_start := state.page_start()
	page_end := state.page_end()

	if items.len == 0 {
		empty_content := pad_or_truncate('  (无匹配命令)', cols - 4)
		lines << '${fg_border}│${ansi_reset}${fg_gray}${empty_content}${ansi_reset}${fg_border}│${ansi_reset}'
		for _ in 1 .. page_size {
			lines << render_nushell_empty_row(specs)
		}
	} else {
		for i in page_start .. page_end {
			e := items[i]
			is_sel := (i == state.cursor_idx)
			lines << render_nushell_row(e, specs, is_sel)
		}
		// 补齐空白行，确保即使数据不满一屏，底部与顶部也不会跳动
		for _ in (page_end - page_start) .. page_size {
			lines << render_nushell_empty_row(specs)
		}
	}

	// 7. 底边
	lines << render_nushell_border_bottom(specs)

	// 8. 底栏按键提示与分页状态
	left_str := ' ${fg_accent}[Tab]${ansi_reset} 来源 ' +
		'${fg_accent}[←/→]${ansi_reset} 环境 ' +
		'${fg_accent}[↑/↓]${ansi_reset} 移动 ' +
		'${fg_accent}[PgUp/PgDn]${ansi_reset} 翻页 ' +
		'${fg_accent}[Enter]${ansi_reset} 详情 ' +
		'${fg_accent}[/]${ansi_reset} 搜索 ' +
		'${fg_accent}[q]${ansi_reset} 退出'

	cur_p := state.current_page() + 1
	tot_p := state.total_pages()
	stat_msg := '第 ${cur_p}/${tot_p} 页 · ${page_size}条/屏 · 共 ${items.len} 条'

	vis_left := term.printable_len(left_str)
	vis_stat := term.printable_len(stat_msg)

	mut foot_line := ''
	if cols > vis_left + vis_stat + 2 {
		gap := cols - vis_left - vis_stat - 1
		foot_line = '${left_str}${' '.repeat(gap)}${fg_yellow}${stat_msg}${ansi_reset}'
	} else if cols > vis_stat + 10 {
		short_left := ' ${fg_accent}[PgUp/PgDn]${ansi_reset} 翻页 ${fg_accent}[q]${ansi_reset} 退出'
		vis_short := term.printable_len(short_left)
		gap := if cols > vis_short + vis_stat { cols - vis_short - vis_stat - 1 } else { 1 }
		foot_line = '${short_left}${' '.repeat(gap)}${fg_yellow}${stat_msg}${ansi_reset}'
	} else {
		foot_line = pad_or_truncate('${fg_yellow}${stat_msg}${ansi_reset}', cols)
	}
	lines << foot_line

	// 9. 组装整屏内容并严格保证行数不超过 rows
	max_lines := if rows > 0 { rows } else { lines.len }
	display_lines := if lines.len > max_lines { lines[..max_lines] } else { lines }

	mut sb := strings.new_builder(cols * rows * 2)
	sb.write_string('\x1b[H') // 光标归位至 (1, 1)

	for idx, line in display_lines {
		sb.write_string('\x1b[2K') // 清空整行防止上一帧残影
		sb.write_string(line)
		// 关键：最后一行绝不输出换行符，避免终端向上滚屏导致顶部 Header 滚出屏幕
		if idx < display_lines.len - 1 {
			sb.write_string('\r\n')
		}
	}

	// 10. 详情浮层（居中覆盖）
	if state.show_detail && items.len > 0 && state.cursor_idx < items.len {
		cur_entry := items[state.cursor_idx]
		sb.write_string(render_modal(cur_entry, cols, rows))
	}

	return sb.str()
}

fn render_nushell_border_top(specs []TableColSpec) string {
	mut sb := strings.new_builder(128)
	sb.write_string('${fg_border}╭')
	for i, spec in specs {
		sb.write_string('─'.repeat(spec.width + 2))
		if i < specs.len - 1 {
			sb.write_string('┬')
		}
	}
	sb.write_string('╮${ansi_reset}')
	return sb.str()
}

fn render_nushell_header(specs []TableColSpec) string {
	mut sb := strings.new_builder(128)
	sb.write_string('${fg_border}│${ansi_reset}')
	for spec in specs {
		title_padded := pad_or_truncate(spec.title, spec.width)
		sb.write_string(' ${ansi_bold}${fg_white}${title_padded}${ansi_reset} ${fg_border}│${ansi_reset}')
	}
	return sb.str()
}

fn render_nushell_border_mid(specs []TableColSpec) string {
	mut sb := strings.new_builder(128)
	sb.write_string('${fg_border}├')
	for i, spec in specs {
		sb.write_string('─'.repeat(spec.width + 2))
		if i < specs.len - 1 {
			sb.write_string('┼')
		}
	}
	sb.write_string('┤${ansi_reset}')
	return sb.str()
}

fn render_nushell_border_bottom(specs []TableColSpec) string {
	mut sb := strings.new_builder(128)
	sb.write_string('${fg_border}╰')
	for i, spec in specs {
		sb.write_string('─'.repeat(spec.width + 2))
		if i < specs.len - 1 {
			sb.write_string('┴')
		}
	}
	sb.write_string('╯${ansi_reset}')
	return sb.str()
}

fn render_nushell_row(e model.Entry, specs []TableColSpec, is_sel bool) string {
	mut sb := strings.new_builder(256)
	bg := if is_sel { bg_sel } else { '' }
	cursor_prefix := if is_sel { '${fg_accent}❯ ' } else { '  ' }

	name_col := cursor_prefix + pad_or_truncate(e.name, specs[0].width - 2)
	src_color := source_color(e.source)
	src_col := '${src_color}' + pad_or_truncate(e.source, specs[1].width)
	scope_col := pad_or_truncate(e.scope, specs[2].width)
	ver_col := pad_or_truncate(if e.version.len > 0 { e.version } else { '—' }, specs[3].width)
	inst_col := pad_or_truncate(e.installed_at, specs[4].width)

	desc_text := if e.description.len > 0 { e.description } else { e.realpath }
	desc_col := pad_or_truncate(desc_text, specs[5].width)

	vals := [name_col, src_col, scope_col, ver_col, inst_col, desc_col]

	sb.write_string('${fg_border}│${ansi_reset}')
	for i, val in vals {
		sb.write_string('${bg} ${val}${ansi_reset}${bg} ${ansi_reset}${fg_border}│${ansi_reset}')
	}
	return sb.str()
}

fn render_nushell_empty_row(specs []TableColSpec) string {
	mut sb := strings.new_builder(128)
	sb.write_string('${fg_border}│')
	for spec in specs {
		sb.write_string(' '.repeat(spec.width + 2))
		sb.write_string('│')
	}
	sb.write_string('${ansi_reset}')
	return sb.str()
}

// render_modal 渲染居中命令详情浮层。
fn render_modal(e model.Entry, cols int, rows int) string {
	modal_w := if cols > 70 { 68 } else { cols - 4 }
	content_w := modal_w - 4
	modal_h := 14

	start_y := if rows > modal_h { (rows - modal_h) / 2 } else { 2 }
	start_x := if cols > modal_w { (cols - modal_w) / 2 } else { 2 }

	mut sb := strings.new_builder(512)

	draw_box_line := fn [start_x] (y int, content string) string {
		return '\x1b[${y};${start_x}H${content}'
	}

	// 弹窗顶框
	title := ' 命令详情: ${e.name} '
	mut top_line := strings.new_builder(128)
	top_line.write_string('${bg_modal}${fg_accent}╭─${ansi_bold}${title}${ansi_reset}${bg_modal}${fg_accent}')
	rem_w := modal_w - 3 - term.printable_len(title)
	if rem_w > 0 {
		top_line.write_string('─'.repeat(rem_w))
	}
	top_line.write_string('╮${ansi_reset}')
	sb.write_string(draw_box_line(start_y, top_line.str()))

	// 属性行
	lines := [
		'命令名称:   ${e.name}',
		'归属来源:   ${e.source} (${e.origin})',
		'二级分类:   ${if e.scope.len > 0 { e.scope } else { '—' }}',
		'版本编号:   ${if e.version.len > 0 { e.version } else { '—' }}',
		'安装时间:   ${if e.installed_at.len > 0 { e.installed_at } else { '—' }}',
		'真实路径:   ${e.realpath}',
		'PATH 生效:  ${if e.in_path {
			'${fg_cyan}是 (当前 PATH 可直接执行)${ansi_reset}'
		} else {
			'${fg_yellow}否 (未在当前 PATH 中)${ansi_reset}'
		}}',
		'功能描述:   ${if e.description.len > 0 { e.description } else { '—' }}',
	]

	for i, ln in lines {
		y := start_y + 1 + i
		padded := pad_or_truncate(ln, content_w)
		sb.write_string(draw_box_line(y, '${bg_modal}${fg_accent}│${ansi_reset}${bg_modal}  ${fg_white}${padded} ${fg_accent}│${ansi_reset}'))
	}

	// 分隔与提示行
	mid_y := start_y + lines.len + 1
	mid_border := '${bg_modal}${fg_accent}├' + '─'.repeat(modal_w - 2) + '┤${ansi_reset}'
	sb.write_string(draw_box_line(mid_y, mid_border))

	hint_y := mid_y + 1
	hint_text := pad_or_truncate('按 Enter / Esc / q 关闭详情卡片', content_w)
	sb.write_string(draw_box_line(hint_y, '${bg_modal}${fg_accent}│${ansi_reset}${bg_modal}  ${fg_gray}${hint_text} ${fg_accent}│${ansi_reset}'))

	bot_y := hint_y + 1
	bot_border := '${bg_modal}${fg_accent}╰' + '─'.repeat(modal_w - 2) + '╯${ansi_reset}'
	sb.write_string(draw_box_line(bot_y, bot_border))

	return sb.str()
}
