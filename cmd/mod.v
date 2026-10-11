module cmd

import strings

pub struct Context {
pub:
	verbose bool
	version string
}

pub struct Command {
pub:
	name        string
	usage       string
	description string
}

// commands 返回全部已注册的子命令。
pub fn commands() []Command {
	return [
		Command{ name: 'hello', usage: 'hello [name]', description: '向 name 问好（默认 world）。' },
		Command{ name: 'version', usage: 'version', description: '打印版本信息。' },
		Command{ name: 'help', usage: 'help', description: '显示帮助。' },
	]
}

// usage 生成顶层帮助文本。
pub fn usage() string {
	mut sb := strings.new_builder(128)
	sb.writeln('Usage: cmds [options] <command> [args]')
	sb.writeln('\nCommands:')
	for c in commands() {
		sb.writeln('  ${pad(c.usage, 16)}${c.description}')
	}
	return sb.str()
}

// pad 将 s 用空格补齐到至少 width 字节宽。
fn pad(s string, width int) string {
	if s.len >= width {
		return s
	}
	return s + ' '.repeat(width - s.len)
}

// run 按第一个位置参数分发子命令；用法错误打印 usage 并 exit(2)。
pub fn run(ctx Context, args []string) ! {
	if args.len == 0 {
		eprintln(usage())
		exit(2)
	}
	match args[0] {
		'hello' { hello_cmd(ctx, args[1..])! }
		'version' { version_cmd(ctx)! }
		'help' { println(usage()) }
		else {
			eprintln('cmds: unknown subcommand: ${args[0]}')
			eprintln(usage())
			exit(2)
		}
	}
}
