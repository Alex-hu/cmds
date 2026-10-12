module main

import cmd
import flag
import os

const version = '0.1.0'

fn main() {
	// 区分全局 flag 与子命令及其参数，避免全局 parser 截获子命令的 --help
	mut subcmd_idx := -1
	for i in 1 .. os.args.len {
		if !os.args[i].starts_with('-') {
			subcmd_idx = i
			break
		}
	}

	global_args := if subcmd_idx != -1 { os.args[..subcmd_idx] } else { os.args }
	sub_args := if subcmd_idx != -1 { os.args[subcmd_idx..] } else { []string{} }

	mut fp := flag.new_flag_parser(global_args)
	fp.application('cmds')
	fp.version(version)
	fp.description('索引并查询本机已安装命令，按来源分类。')
	fp.skip_executable()
	fp.allow_unknown_args()
	verbose := fp.bool('verbose', `v`, false, 'enable verbose output')
	fp.finalize() or {
		eprintln(fp.usage())
		eprintln('error: ${err}')
		exit(2)
	}

	if sub_args.len == 0 {
		eprintln(cmd.usage())
		exit(2)
	}

	ctx := cmd.Context{
		verbose: verbose
	}
	cmd.run(ctx, sub_args) or {
		eprintln('cmds: ${err}')
		exit(1)
	}
}
