module main

import cmd
import flag
import os

const version = '0.1.0'

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application('cmds')
	fp.version(version)
	fp.description('示例命令行工具骨架。')
	fp.skip_executable()
	verbose := fp.bool('verbose', `v`, false, 'enable verbose output')
	args := fp.finalize() or {
		eprintln(fp.usage())
		eprintln('error: ${err}')
		exit(2)
	}
	ctx := cmd.Context{
		verbose: verbose
		version: version
	}
	cmd.run(ctx, args) or {
		eprintln('cmds: ${err}')
		exit(1)
	}
}
