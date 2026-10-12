module cmd

import x.json2

fn test_search_command_registered() {
	cmds := commands()
	mut found_search := false
	for c in cmds {
		if c.name == 'search' {
			found_search = true
			assert c.usage.contains('search')
			assert c.description.contains('检索')
		}
	}
	assert found_search
}

fn test_search_usage_output() {
	u := usage()
	assert u.contains('search [options] <query...>')
}

fn test_search_json_serialization() {
	item := SearchJsonItem{
		name:         'browser-use'
		ecosystem:    'python'
		manager:      'anaconda3'
		scope:        'py312'
		version:      '0.1.0'
		description:  'Browser automation agent'
		installed_at: '2026-03-01'
		in_path:      false
		how_to_run:   '/opt/anaconda3/envs/py312/bin/browser-use'
		switch_env:   'conda activate py312'
		realpath:     '/opt/anaconda3/envs/py312/bin/browser-use'
	}
	encoded := json2.encode([item], prettify: true)
	assert encoded.contains('"name": "browser-use"')
	assert encoded.contains('"manager": "anaconda3"')
	assert encoded.contains('"switch_env": "conda activate py312"')
	assert encoded.contains('"in_path": false')
}
