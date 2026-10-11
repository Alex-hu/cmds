module cmd

import flag
import internal.store
import os
import strings

// list_cmd 从索引读取并打印命令清单（M2 提供完整 report/JSON/CJK 对齐，此处为可用版）。
fn list_cmd(ctx Context, args []string) ! {
	mut fp := flag_parser_for('list', args)
	src := fp.string('source', `s`, '', '按来源过滤：brew/npm/conda/cargo/go/rvm/app/system/manual')
	scope := fp.string('scope', 0, '', '按二级分类过滤（conda 环境名 / node 版本标识）')
	rest := fp.finalize() or {
		eprintln('cmds: ${err}')
		exit(2)
	}
	if rest.len > 0 {
		eprintln('cmds: list 不接受位置参数: ${rest[0]}')
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
	defer { st.close() }
	entries := st.query(src, scope, '') or {
		eprintln('cmds: 查询失败: ${err}')
		exit(1)
	}
	if entries.len == 0 {
		println('(无匹配条目)')
		return
	}
	if ctx.verbose {
		eprintln("source='${src}' scope='${scope}'")
	}

	mut sb := strings.new_builder(1024)
	sb.writeln('${th('NAME', 24)}${th('SOURCE', 8)}${th('SCOPE', 22)}${th('VERSION', 12)}${th('INSTALLED', 18)}PATH')
	for e in entries {
		sb.writeln('${td(e.name, 24)}${td(e.source, 8)}${td(e.scope, 22)}${td(e.version, 12)}${td(e.installed_at, 18)}${e.realpath}')
	}
	println(sb.str())
}

// flag_parser_for 为子命令构造独立的 flag 解析器（args 不含子命令名）。
fn flag_parser_for(name string, args []string) flag.FlagParser {
	mut fp := flag.new_flag_parser([name, ...args])
	fp.application('cmds ' + name)
	fp.skip_executable()
	return fp
}

fn th(s string, w int) string {
	return pad(s, w + 2)
}

fn td(s string, w int) string {
	return pad(s, w + 2)
}
