module store

import internal.model
import thirdparty.sqlite
import time

// schema_version 是当前索引库的 schema 版本，对应 SQLite 的 PRAGMA user_version。
pub const schema_version = 2

// Store 是 SQLite 索引库的读写句柄（库文件路径见 DESIGN.md「数据模型」节，测试可用 ':memory:'）。
pub struct Store {
mut:
	db sqlite.DB
}

// insert_entry_sql 写入一条 entry；可空 text 列用 nullif(?, '') 保证空串存为 NULL，
// 读回时 NULL 与空串都映射为 ''（语义相等）。
const insert_entry_sql = "insert into entries (name, source_id, ecosystem, manager, origin, scope, realpath, in_path,
	version, description, installed_at, size_bytes, kind)
	values (?, ?, ?, ?, ?, nullif(?, ''), ?, ?, nullif(?, ''), nullif(?, ''), nullif(?, ''), ?, nullif(?, ''))"

// select_entry_sql 读回 entry 全字段（不含 occurrences，后者单独查询后挂载）。
const select_entry_sql = 'select id, name, source_id, ecosystem, manager, origin, scope, realpath, in_path, version,
	description, installed_at, size_bytes, kind from entries'

// open 打开（必要时创建）path 处的索引库：user_version 为 0 且无表时建当前 schema；
// user_version 不等于 schema_version 时丢弃全部表重建。返回的 Store 用完须调用 close()。
pub fn open(path string) !Store {
	mut db := sqlite.connect(path)!
	version := db.q_int('pragma user_version') or { 0 }
	if version == schema_version {
		return Store{
			db: db
		}
	}
	// version 为 0（全新空库或无版本的旧库）或不等于当前版本：清掉已有表后重建。
	drop_all(mut db)!
	create_schema(mut db)!
	return Store{
		db: db
	}
}

// save_all 在单事务内全量替换索引：DELETE entries/occurrences/meta 后 INSERT 全部 Entry，
// occurrences 挂到对应 entry（靠 last_insert_rowid 取新 entry 的 id），最后写
// meta 的 built_at（当前时间）与 count（条目数）；中途失败整体回滚。
pub fn (mut s Store) save_all(entries []model.Entry) ! {
	s.db.exec('begin')!
	s.do_save_all(entries) or {
		s.db.exec('rollback') or {}
		return err
	}
	s.db.exec('commit')!
}

// do_save_all 是 save_all 的事务体（调用方负责 BEGIN/COMMIT/回滚）。
fn (mut s Store) do_save_all(entries []model.Entry) ! {
	s.db.exec_param_many('delete from occurrences', []string{})!
	s.db.exec_param_many('delete from entries', []string{})!
	s.db.exec_param_many('delete from meta', []string{})!
	for e in entries {
		s.db.exec_param_many(insert_entry_sql, [
			e.name,
			e.source_id,
			e.ecosystem,
			e.manager,
			e.origin,
			e.scope,
			e.realpath,
			if e.in_path { '1' } else { '0' },
			e.version,
			e.description,
			e.installed_at,
			e.size_bytes.str(),
			e.kind,
		])!
		entry_id := s.db.last_insert_rowid()
		for o in e.occurrences {
			s.db.exec_param_many('insert into occurrences (entry_id, path, path_priority) values (?, ?, ?)', [
				entry_id.str(),
				o.path,
				o.path_priority.str(),
			])!
		}
	}
	s.db.exec_param_many("insert into meta (key, value) values ('built_at', ?)", [
		time.now().format(),
	])!
	s.db.exec_param_many("insert into meta (key, value) values ('count', ?)", [entries.len.str()])!
}

// load_all 读回全部 Entry（含 occurrences，按 path_priority 升序），等价于 query 全空参。
pub fn (s Store) load_all() ![]model.Entry {
	return s.query('', '', '', '')
}

// query 组合过滤：ecosystem/manager/scope/name_contains 传空串表示该维度不过滤；
// name_contains 用 LIKE '%'||?||'%' 匹配 name 子串。返回按 name、realpath 排序，
// occurrences 按 path_priority 升序挂载。
pub fn (s Store) query(ecosystem string, manager string, scope string, name_contains string) ![]model.Entry {
	mut q := select_entry_sql + ' where 1=1'
	mut params := []string{}
	if ecosystem != '' {
		q += ' and ecosystem = ?'
		params << ecosystem
	}
	if manager != '' {
		q += ' and manager = ?'
		params << manager
	}
	if scope != '' {
		q += ' and scope = ?'
		params << scope
	}
	if name_contains != '' {
		q += " and name like '%'||?||'%'"
		params << name_contains
	}
	q += ' order by name, realpath'
	rows := s.db.exec_param_many(q, params)!
	mut out := []model.Entry{cap: rows.len}
	mut by_id := map[int]int{}
	for i, r in rows {
		by_id[r.get_int('id')] = i
		out << row_to_entry(r)
	}
	// 一次查出全部 occurrences（按 path_priority 升序），按 entry_id 分组挂载
	occs := s.db.exec('select entry_id, path, path_priority from occurrences order by path_priority asc, path asc')!
	for o in occs {
		if i := by_id[o.get_int('entry_id')] {
			out[i].occurrences << model.Occurrence{
				path:          o.get_string('path')
				path_priority: o.get_int('path_priority')
			}
		}
	}
	return out
}

// meta_get 读 meta 表的 value；key 不存在返回 none（存在但值为空串返回 some('')）。
pub fn (s Store) meta_get(key string) ?string {
	rows := s.db.exec_param_many('select value from meta where key = ?', [key]) or {
		return none
	}
	if rows.len == 0 {
		return none
	}
	return rows[0].get_string('value')
}

// close 关闭底层 SQLite 连接（关闭失败静默忽略，资源由进程退出兜底）。
pub fn (mut s Store) close() {
	s.db.close() or {}
}

// row_to_entry 把一行查询结果转成 model.Entry；NULL 列经 get_string 已是 ''，
// size_bytes 用字符串读回再 u64()（get_int 是 32 位 int，大文件会被截断）。
fn row_to_entry(r sqlite.Row) model.Entry {
	return model.Entry{
		name:         r.get_string('name')
		source_id:    r.get_string('source_id')
		ecosystem:    r.get_string('ecosystem')
		manager:      r.get_string('manager')
		origin:       r.get_string('origin')
		scope:        r.get_string('scope')
		realpath:     r.get_string('realpath')
		occurrences:  []model.Occurrence{}
		in_path:      r.get_int('in_path') != 0
		version:      r.get_string('version')
		description:  r.get_string('description')
		installed_at: r.get_string('installed_at')
		size_bytes:   r.get_string('size_bytes').u64()
		kind:         r.get_string('kind')
	}
}

// drop_all 删除库中全部用户表/视图/触发器/索引（保留 sqlite_* 内部对象），
// 按 trigger→view→index→table 的顺序避免依赖冲突；空库时是 no-op。
fn drop_all(mut db sqlite.DB) ! {
	rows := db.exec("select type, name from sqlite_master where name not like 'sqlite_%'
		order by case type when 'trigger' then 0 when 'view' then 1 when 'index' then 2 else 3 end")!
	for r in rows {
		db.exec('drop ${r.get_string('type')} if exists "${r.get_string('name')}";')!
	}
}

// create_schema 建当前版本的表/索引并把 user_version 写为 schema_version。
// 表名/列名与 DESIGN.md「数据模型」的 schema v2 一致；exec 一次只执行一条语句
// （底层 prepare_v2 不支持多语句），故逐条调用。
fn create_schema(mut db sqlite.DB) ! {
	db.exec('create table entries (
		id            integer primary key,
		name          text not null,
		source_id     text not null,
		ecosystem     text not null,
		manager       text not null,
		origin        text not null,
		scope         text,
		realpath      text not null,
		in_path       integer not null default 0,
		version       text,
		description   text,
		installed_at  text,
		size_bytes    integer,
		kind          text
	)')!
	db.exec('create unique index ux_entry on entries(name, realpath)')!
	db.exec('create index ix_name on entries(name)')!
	db.exec('create index ix_hierarchy on entries(ecosystem, manager, scope)')!
	db.exec('create table occurrences (
		entry_id      integer not null references entries(id),
		path          text not null,
		path_priority integer not null
	)')!
	db.exec('create table meta (key text primary key, value text)')!
	db.exec('pragma user_version = ${schema_version}')!
}
