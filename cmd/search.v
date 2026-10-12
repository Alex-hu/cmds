module cmd

import internal.model
import internal.store
import internal.ui
import os
import strings
import x.json2

// SearchJsonItem 是面向 AI/工具调用的结构化 JSON 输出对象。
struct SearchJsonItem {
pub:
	name         string
	ecosystem    string
	manager      string
	scope        string
	version      string
	description  string
	installed_at string
	in_path      bool
	how_to_run   string
	switch_env   string
	realpath     string
}

// search_cmd 执行针对 AI 与人类的多词智能搜索。
fn search_cmd(ctx Context, args []string) ! {
	_ = ctx
	mut fp := flag_parser_for('search', args)
	limit := fp.int('limit', `n`, 10, '最多返回的匹配条目数 (默认 10，0 为无限制)')
	all := fp.bool('all', `a`, false, '返回所有匹配结果（不限制条数）')
	json_out := fp.bool('json', 0, false, '以标准 JSON 数组格式输出（适合 AI 工具调用）')
	table_out := fp.bool('table', 0, false, '以类似 list 的表格样式输出')
	eco := fp.string('ecosystem', `e`, '', '按生态过滤：node/python/go/rust/brew/system/app/manual')
	mgr := fp.string('manager', `m`, '', '按包管理器过滤：anaconda3/miniforge3/uv/fnm/pnpm/cargo/go/brew/system')
	scope := fp.string('scope', 0, '', '按三级环境/版本过滤')
	in_path_only := fp.bool('in-path', 0, false, '仅展示当前 PATH 中可直接执行的命令')

	rest := fp.finalize() or {
		eprintln('cmds: ${err}')
		exit(2)
	}

	query := rest.join(' ').trim_space()
	if query == '' {
		eprintln('cmds: search 请提供搜索关键词。例如: cmds search agent')
		eprintln(fp.usage())
		exit(2)
	}

	db_path := index_db_path()
	if !os.exists(db_path) {
		eprintln('cmds: 未找到索引，请先运行 cmds update')
		exit(1)
	}

	mut st := store.open(db_path) or {
		eprintln('cmds: 打开索引失败: ${err}')
		exit(1)
	}
	defer {
		st.close()
	}

	// 检索与加载候选数据
	mut candidate_entries := st.query(eco, mgr, scope, '') or {
		eprintln('cmds: 检索失败: ${err}')
		exit(1)
	}

	if in_path_only {
		candidate_entries = candidate_entries.filter(it.in_path)
	}

	// 执行加权与多词排序检索
	all_ranked := model.rank_search(candidate_entries, query)

	// 截取 limit
	effective_limit := if all || limit <= 0 { all_ranked.len } else { limit }
	final_results := if all_ranked.len > effective_limit {
		all_ranked[..effective_limit]
	} else {
		all_ranked
	}

	if json_out {
		mut json_items := []SearchJsonItem{cap: final_results.len}
		for r in final_results {
			json_items << SearchJsonItem{
				name:         r.entry.name
				ecosystem:    r.entry.ecosystem
				manager:      r.entry.manager
				scope:        r.entry.scope
				version:      r.entry.version
				description:  r.entry.description
				installed_at: r.entry.installed_at
				in_path:      r.entry.in_path
				how_to_run:   r.how_to_run
				switch_env:   r.switch_env
				realpath:     r.entry.realpath
			}
		}
		println(json2.encode(json_items, prettify: true))
		return
	}

	if table_out {
		mut table_entries := []model.Entry{cap: final_results.len}
		for r in final_results {
			table_entries << r.entry
		}
		println(ui.render_static_table(table_entries))
		return
	}

	// 默认 AI 友好格式输出 (语义清晰、高信噪比、零截断)
	if final_results.len == 0 {
		println('No commands matching "${query}".')
		return
	}

	println('Found ${final_results.len} command(s) matching "${query}":\n')
	mut sb := strings.new_builder(final_results.len * 256)

	for idx, r in final_results {
		e := r.entry
		ver_str := if e.version != '' { ' (v${e.version})' } else { '' }
		path_status := if e.in_path { '[Ready in PATH]' } else { '[Not in PATH]' }

		sb.writeln('${idx + 1}. ${e.name}${ver_str} ${path_status}')

		// Ecosystem & Manager & Scope
		eco_mgr := if e.ecosystem == e.manager || e.manager == '' {
			e.ecosystem
		} else {
			'${e.ecosystem} / ${e.manager}'
		}
		scope_part := if e.scope != '' { ' (scope: ${e.scope})' } else { '' }
		sb.writeln('   Ecosystem:   ${eco_mgr}${scope_part}')

		// Description
		desc := if e.description != '' { e.description } else { '—' }
		sb.writeln('   Description: ${desc}')

		// Switch Env (仅当需要环境切换时展示)
		if r.switch_env != '' {
			sb.writeln('   Switch Env:  ${r.switch_env}')
		}

		// Execute
		sb.writeln('   Execute:     ${r.how_to_run}')

		// Realpath
		sb.writeln('   Realpath:    ${e.realpath}')

		if idx < final_results.len - 1 {
			sb.writeln('')
		}
	}

	print(sb.str())
}
