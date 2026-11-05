module clip

fn test_osc52_sequence() {
	seq := osc52_sequence('echo hello')
	assert seq.starts_with('\x1b]52;c;')
	assert seq.ends_with('\x07')
	assert seq.contains('ZWNobyBoZWxsbw==')
}

fn test_copy() {
	ok := copy('cmds_test_payload_123')
	assert ok == true
}
