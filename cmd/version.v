module cmd

// tool_version 是 cmds 自身版本，与 v.mod 保持一致。
pub const tool_version = '0.1.0'

fn version_cmd(ctx Context) ! {
	if ctx.verbose {
		eprintln('ctx: verbose=${ctx.verbose}')
	}
	println(tool_version)
}
