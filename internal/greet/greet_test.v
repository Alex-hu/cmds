module greet

fn test_greet() {
	assert greet('') == 'hello, world'
	assert greet('v') == 'hello, v'
}
