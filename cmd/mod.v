module cmd

import strings

// Context 携带全局选项，由 main 构造后传给各子命令。
pub struct Context {
pub:
	verbose bool
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
		Command{ name: 'update', usage: 'update [--deep]', description: '重建索引（deep 探测 M4 提供）' },
		Command{ name: 'list', usage: 'list [--source S] [--scope E]', description: '列出已索引命令（默认读缓存）' },
		Command{ name: 'search', usage: 'search [options] <query...>', description: '智能检索命令（支持多词与环境切换提示）' },
		Command{ name: 'version', usage: 'version', description: '打印版本信息。' },
		Command{ name: 'help', usage: 'help', description: '显示帮助。' },
	]
}

// usage 生成顶层帮助文本。
pub fn usage() string {
	mut sb := strings.new_builder(256)
	sb.writeln('Usage: cmds [options] <command> [args]')
	sb.writeln('\nCommands:')
	for c in commands() {
		sb.writeln('  ${pad(c.usage, 32)}${c.description}')
	}
	sb.writeln('\n先运行 cmds update 建立索引。')
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
		'update' { update_cmd(ctx, args[1..])! }
		'list' { list_cmd(ctx, args[1..])! }
		'search' { search_cmd(ctx, args[1..])! }
		'version' { version_cmd(ctx)! }
		'help' { println(usage()) }
		else {
			eprintln('cmds: unknown subcommand: ${args[0]}')
			eprintln(usage())
			exit(2)
		}
	}
}
