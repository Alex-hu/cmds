module cmd

import internal.greet

fn hello_cmd(ctx Context, args []string) ! {
	if args.len > 1 {
		return error('hello: too many arguments')
	}
	name := if args.len == 1 { args[0] } else { '' }
	if ctx.verbose {
		eprintln('greeting: ${name}')
	}
	println(greet.greet(name))
}
