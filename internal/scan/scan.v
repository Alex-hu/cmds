module scan

import os

// 文件类型与权限掩码（POSIX st_mode），用于 stat 结果判断。
const s_ifmt = 0o170000 // 文件类型位掩码
const s_ifreg = 0o100000 // 普通文件
const exec_any = 0o111 // 任一执行位（user/group/other 任一为 1）

// PathDir 记录 PATH 中的一个目录：原样保留的路径、在 PATH 中的序号与存在性。
pub struct PathDir {
pub:
	dir      string // 绝对路径（原样保留，不去重后变化）
	priority int    // 在 PATH 中的序号，0 起
	exists   bool   // os.is_dir 结果
}

// parse_path 解析 PATH 环境变量串（'a:b:c'）：跳过空段；按目录去重（保留首次出现，priority 取首次序号）。
pub fn parse_path(path_env string) []PathDir {
	mut out := []PathDir{}
	mut seen := map[string]bool{}
	mut priority := 0
	for seg in path_env.split(':') {
		if seg == '' || seg in seen {
			continue
		}
		seen[seg] = true
		out << PathDir{
			dir:      seg
			priority: priority
			exists:   os.is_dir(seg)
		}
		priority++
	}
	return out
}

// FileInfo 是扫描到的一个可执行文件条目（目录只列一层，不递归）。
pub struct FileInfo {
pub:
	name       string // 文件名
	dir        string // 所扫目录
	path       string // dir + '/' + name（原样）
	realpath   string // os.real_path 解析后的真实路径
	kind       string // 'script'（shebang 开头）| 'binary'
	size_bytes u64
	mtime      i64 // unix 秒
}

// scan_dir 列出目录中的可执行文件：仅普通文件且带任一执行位；realpath 解析符号链接；
// 读文件前两字节判断 shebang。不可读/损坏的项静默跳过。
pub fn scan_dir(dir string) []FileInfo {
	names := os.ls(dir) or { return []FileInfo{} }
	mut out := []FileInfo{cap: names.len}
	for name in names {
		if info := to_file_info(dir, name) {
			out << info
		}
	}
	return out
}

// to_file_info 判断单个目录项是否为可执行普通文件（stat 跟随符号链接，损坏链接 stat 失败即跳过）；
// 是则返回条目，否则返回 none。
fn to_file_info(dir string, name string) ?FileInfo {
	path := dir + '/' + name
	st := os.stat(path) or { return none }
	// 仅普通文件（目录/设备等即便带执行位也不算）且任一执行位为 1
	if (st.mode & s_ifmt) != s_ifreg || (st.mode & exec_any) == 0 {
		return none
	}
	mut f := os.open(path) or { return none } // 不可读则静默跳过
	mut head := []u8{len: 2, init: u8(0)}
	nread := f.read(mut head) or {
		f.close()
		return none
	}
	f.close()
	kind := if nread >= 2 && head[0] == `#` && head[1] == `!` { 'script' } else { 'binary' }
	return FileInfo{
		name:       name
		dir:        dir
		path:       path
		realpath:   os.real_path(path)
		kind:       kind
		size_bytes: st.size
		mtime:      st.mtime
	}
}

// ScanSlot 是 scan_dirs 并行任务的回传载体：idx 记录输入目录序号，用于按输入顺序归位。
struct ScanSlot {
	idx   int
	files []FileInfo
}

// scan_dirs 并行扫描多个目录（spawn + channel），返回结果顺序必须与输入目录顺序一致（预分配槽位）。
// 目录不存在/不可读返回空。
pub fn scan_dirs(dirs []string) []FileInfo {
	n := dirs.len
	if n == 0 {
		return []FileInfo{}
	}
	ch := chan ScanSlot{cap: n}
	for i in 0 .. n {
		spawn scan_slot_task(ch, i, dirs[i])
	}
	mut slots := [][]FileInfo{len: n, init: []FileInfo{}}
	for _ in 0 .. n {
		slot := <-ch
		slots[slot.idx] = slot.files
	}
	mut out := []FileInfo{}
	for i in 0 .. n {
		out << slots[i]
	}
	return out
}

// scan_slot_task 扫描单个目录并把（槽位号, 结果）送回 channel。
fn scan_slot_task(ch chan ScanSlot, idx int, dir string) {
	ch <- ScanSlot{
		idx:   idx
		files: scan_dir(dir)
	}
}
