module scan

import os
import rand

// new_fixture_dir 创建带随机名的临时根目录，测试在其内自建目录树，不依赖真机状态。
fn new_fixture_dir() string {
	root := os.join_path(os.temp_dir(), 'cmds_scan_${rand.uuid_v4()}')
	os.mkdir(root) or { panic(err) }
	return root
}

// make_exec 写文件并加全部执行位（0o755）。
fn make_exec(path string, content string) {
	os.write_file(path, content) or { panic(err) }
	os.chmod(path, 0o755) or { panic(err) }
}

// names_of 提取 FileInfo 列表的文件名（os.ls 返回顺序与 readdir 一致，断言前先排序）。
fn names_of(infos []FileInfo) []string {
	mut names := infos.map(it.name)
	names.sort()
	return names
}

fn test_parse_path_skips_empty_segments() {
	// 空段（连续分隔符、首尾分隔符、整串为空）都不产生条目
	assert parse_path('').len == 0
	assert parse_path(':').len == 0
	assert parse_path(':::').len == 0
	res := parse_path('/a::/b:')
	assert res.len == 2
	assert res[0].dir == '/a'
	assert res[0].priority == 0
	assert res[1].dir == '/b'
	assert res[1].priority == 1
}

fn test_parse_path_dedupes_keeps_first_priority() {
	// 重复目录只保留首次出现，priority 取首次序号（对去重后的序列 0 起连续编号）
	res := parse_path('/x:/y:/x:/z')
	assert res.len == 3
	assert res[0].dir == '/x'
	assert res[0].priority == 0
	assert res[1].dir == '/y'
	assert res[1].priority == 1
	assert res[2].dir == '/z'
	assert res[2].priority == 2
}

fn test_parse_path_exists_flag() {
	root := new_fixture_dir()
	defer {
		os.rmdir_all(root) or {}
	}
	res := parse_path('${root}:/definitely/no/such/dir')
	assert res.len == 2
	assert res[0].exists == true
	assert res[1].exists == false
}

fn test_scan_dir_scripts_links_and_skips() {
	root := new_fixture_dir()
	defer {
		os.rmdir_all(root) or {}
	}
	script_content := '#!/bin/sh\necho hi\n'
	script := os.join_path(root, 'hello.sh')
	make_exec(script, script_content)
	// 不可执行文件：默认 0o644，无执行位，应跳过
	os.write_file(os.join_path(root, 'plain.txt'), 'no exec bit') or { panic(err) }
	// 指向脚本的符号链接：应出现，realpath 解析到脚本本体
	link := os.join_path(root, 'hello-link')
	os.symlink(script, link) or { panic(err) }
	// 损坏符号链接：stat 失败，应静默跳过
	os.symlink(os.join_path(root, 'nope'), os.join_path(root, 'broken')) or { panic(err) }
	// 子目录（自身带执行位但非普通文件）：应跳过
	os.mkdir(os.join_path(root, 'subdir')) or { panic(err) }
	// 可执行但无 shebang 的文件：kind 应为 binary
	binlike := os.join_path(root, 'binlike')
	make_exec(binlike, 'fake-elf-content')

	res := scan_dir(root)
	assert names_of(res) == ['binlike', 'hello-link', 'hello.sh']

	mut by_name := map[string]FileInfo{}
	for info in res {
		by_name[info.name] = info
		// path 按契约原样拼接，dir 为所扫目录
		assert info.dir == root
		assert info.path == root + '/' + info.name
		assert info.mtime > 0
	}
	script_info := by_name['hello.sh']
	assert script_info.kind == 'script'
	assert script_info.size_bytes == u64(script_content.len)
	assert script_info.realpath == os.real_path(script)
	link_info := by_name['hello-link']
	assert link_info.kind == 'script' // 内容穿透符号链接读取
	assert link_info.realpath == os.real_path(script)
	bin_info := by_name['binlike']
	assert bin_info.kind == 'binary'
}

fn test_scan_dir_missing_returns_empty() {
	assert scan_dir('/definitely/no/such/dir').len == 0
	assert scan_dir('').len == 0
}

fn test_scan_dirs_preserves_input_order() {
	root := new_fixture_dir()
	defer {
		os.rmdir_all(root) or {}
	}
	dir_a := os.join_path(root, 'a')
	dir_empty := os.join_path(root, 'e')
	dir_b := os.join_path(root, 'b')
	for d in [dir_a, dir_empty, dir_b] {
		os.mkdir(d) or { panic(err) }
	}
	make_exec(os.join_path(dir_a, 'aaa.sh'), '#!/bin/sh\n')
	make_exec(os.join_path(dir_b, 'bbb.sh'), '#!/bin/sh\n')
	missing := os.join_path(root, 'missing')

	res := scan_dirs([dir_a, dir_empty, missing, dir_b])
	// 空目录与不存在目录贡献为空；结果顺序与输入目录顺序一致
	assert res.len == 2
	assert res[0].name == 'aaa.sh'
	assert res[0].dir == dir_a
	assert res[1].name == 'bbb.sh'
	assert res[1].dir == dir_b
}

fn test_scan_dirs_empty_input() {
	assert scan_dirs([]string{}).len == 0
	assert scan_dirs(['/definitely/no/such/dir']).len == 0
}
