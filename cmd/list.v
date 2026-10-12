module cmd

import flag
import internal.store
import internal.ui
import os

// list_cmd 从索引读取并打印命令清单（支持 Nushell 风格静态表格与交互式 Tab 浏览器）。
fn list_cmd(ctx Context, args []string) ! {
	mut fp := flag_parser_for('list', args)
	eco := fp.string('ecosystem', `e`, '', '按生态过滤：node/python/go/rust/brew/system/app/manual')
	mgr := fp.string('manager', `m`, '', '按包管理器过滤：fnm/nvm/pnpm/conda/cargo/go/brew/system')
	src := fp.string('source', `s`, '', '按生态或管理器过滤（兼容别名）')
	scope := fp.string('scope', 0, '', '按三级环境/版本过滤（conda 环境名 / node 版本标识）')
	interactive := fp.bool('interactive', `i`, false, '启动交互式 Tab 浏览器 (原型 A2)')
	plain := fp.bool('plain', `p`, false, '强制输出无交互的 Nushell 边框表格')
	rest := fp.finalize() or {
		eprintln('cmds: ${err}')
		exit(2)
	}
	if rest.len > 0 {
		eprintln('cmds: list 不接受位置参数: ${rest[0]}')
		exit(2)
	}

	mut filter_eco := eco
	mut filter_mgr := mgr
	if src != '' {
		if src in ['node', 'python', 'go', 'rust', 'brew', 'system', 'app', 'manual', 'ruby'] {
			if filter_eco == '' {
				filter_eco = src
			}
		} else {
			if filter_mgr == '' {
				filter_mgr = src
			}
		}
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

	// 判断是否进入全屏交互式 Tab 浏览器模式
	is_tty := os.is_atty(0) > 0 && os.is_atty(1) > 0
	should_run_tui := interactive || (is_tty && !plain && filter_eco == '' && filter_mgr == '' && scope == '')

	if should_run_tui {
		all_entries := st.load_all() or {
			eprintln('cmds: 加载索引失败: ${err}')
			exit(1)
		}
		ui.run(all_entries)!
		return
	}

	// 静态查询与 Nushell 风格表格输出
	entries := st.query(filter_eco, filter_mgr, scope, '') or {
		eprintln('cmds: 查询失败: ${err}')
		exit(1)
	}
	if ctx.verbose {
		eprintln("ecosystem='${filter_eco}' manager='${filter_mgr}' scope='${scope}'")
	}
	println(ui.render_static_table(entries))
}

// flag_parser_for 为子命令构造独立的 flag 解析器（args 不含子命令名）。
fn flag_parser_for(name string, args []string) flag.FlagParser {
	mut fp := flag.new_flag_parser([name, ...args])
	fp.application('cmds ' + name)
	fp.skip_executable()
	return fp
}
