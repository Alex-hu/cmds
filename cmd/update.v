module cmd

import internal.model
import internal.scan
import internal.source
import internal.store
import os
import time

// index_db_path 返回索引库路径（CMDS_CACHE_DIR 可覆盖，默认 ~/Library/Caches/cmds/index.db）。
fn index_db_path() string {
	override := os.getenv('CMDS_CACHE_DIR')
	if override != '' {
		return os.join_path(override, 'index.db')
	}
	return os.join_path(os.home_dir(), 'Library', 'Caches', 'cmds', 'index.db')
}

// update_cmd 重建索引：发现 → 归因 → 去重 → 富化 → SQLite 落库。
// 只读文件系统元数据与各源注册信息，不执行任何被索引的二进制。
fn update_cmd(ctx Context, _ []string) ! {
	started := time.ticks()
	srcs := source.all_sources()
	path_dirs := scan.parse_path(os.getenv('PATH'))

	// 扫描目录 = PATH 目录 ∪ 各源 roots（去重，保持确定性顺序）。
	mut all_dirs := []string{}
	mut seen := map[string]bool{}
	for pd in path_dirs {
		if pd.exists && pd.dir != '' && pd.dir !in seen {
			seen[pd.dir] = true
			all_dirs << pd.dir
		}
	}
	for src in srcs {
		for root in src.roots() {
			if root != '' && root !in seen {
				seen[root] = true
				all_dirs << root
			}
		}
	}
	// PATH 目录 realpath 归一化后映射到优先级（符号链接目录等价）。
	mut prio_by_dir := map[string]int{}
	for pd in path_dirs {
		if pd.exists {
			norm := os.real_path(pd.dir)
			if norm !in prio_by_dir {
				prio_by_dir[norm] = pd.priority
			}
		}
	}
	files := scan.scan_dirs(all_dirs)
	if ctx.verbose {
		eprintln('扫描 ${all_dirs.len} 个目录，${files.len} 个文件')
	}

	// 归因 + 组装 entry。
	mut entries := []model.Entry{cap: files.len}
	for f in files {
		attr := attribute_of(srcs, f.realpath) or {
			source.Attribution{
				source_id: 'manual'
				ecosystem: 'manual'
				manager:   'manual'
				origin:    'manual'
				scope:     ''
			}
		}
		dir_norm := os.real_path(f.dir)
		in_path := dir_norm in prio_by_dir
		mut e := model.Entry{
			name:       f.name
			source_id:  attr.source_id
			ecosystem:  attr.ecosystem
			manager:    attr.manager
			origin:     attr.origin
			scope:      attr.scope
			realpath:   f.realpath
			in_path:    in_path
			size_bytes: f.size_bytes
			kind:       f.kind
		}
		if in_path {
			e.occurrences << model.Occurrence{ path: f.path, path_priority: prio_by_dir[dir_norm] }
		}
		entries << e
	}
	entries = model.dedupe(entries)
	if ctx.verbose {
		eprintln('去重后 ${entries.len} 条')
	}

	// 富化：按源分组，各自就地填充；单源失败降级为 warning 不中断。
	mut warnings := 0
	for src in srcs {
		mut mine := entries.filter(it.source_id == src.id())
		if mine.len == 0 {
			continue
		}
		src.enrich(mut mine) or {
			warnings++
			eprintln('cmds: warning: enrich ${src.id()} 失败: ${err}')
			continue
		}
		// enrich 操作的是副本，按 (name, realpath) 写回。
		for enriched in mine {
			for i, e in entries {
				if e.source_id == src.id() && e.name == enriched.name && e.realpath == enriched.realpath {
					entries[i] = enriched
				}
			}
		}
		if ctx.verbose {
			eprintln('${src.id()}: ${mine.len} 条已富化')
		}
	}

	// 落库。
	db_path := index_db_path()
	os.mkdir_all(os.dir(db_path)) or {}
	mut st := store.open(db_path) or {
		return error('打开索引库 ${db_path} 失败: ${err}')
	}
	st.save_all(entries) or {
		return error('写入索引失败: ${err}')
	}
	st.close()
	elapsed := time.ticks() - started
	println('已索引 ${entries.len} 条命令 → ${db_path}（${elapsed}ms，warnings=${warnings}）')
}

// attribute_of 按 priority 顺序轮询各源，首个命中的归因生效。
fn attribute_of(srcs []source.Source, realpath string) ?source.Attribution {
	for src in srcs {
		if attr := src.attribute(realpath) {
			return attr
		}
	}
	return none
}
