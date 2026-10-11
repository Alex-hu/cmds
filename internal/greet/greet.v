module greet

// greet 返回问候语；name 为空时问候 world。
pub fn greet(name string) string {
	if name == '' {
		return 'hello, world'
	}
	return 'hello, ${name}'
}
