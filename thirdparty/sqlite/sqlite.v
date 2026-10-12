module sqlite

#flag darwin -lsqlite3

$if !darwin && !windows {
	#flag -lsqlite3
	#flag -lpthread
	#flag -ldl
}

#include <sqlite3.h>

@[typedef]
struct C.sqlite3 {}

@[typedef]
struct C.sqlite3_stmt {}

fn C.sqlite3_open(&char, &&C.sqlite3) int
fn C.sqlite3_close(&C.sqlite3) int
fn C.sqlite3_errmsg(&C.sqlite3) &char
fn C.sqlite3_prepare_v2(&C.sqlite3, &char, int, &&C.sqlite3_stmt, &&char) int
fn C.sqlite3_step(&C.sqlite3_stmt) int
fn C.sqlite3_finalize(&C.sqlite3_stmt) int
fn C.sqlite3_column_count(&C.sqlite3_stmt) int
fn C.sqlite3_column_name(&C.sqlite3_stmt, int) &char
fn C.sqlite3_column_text(&C.sqlite3_stmt, int) &u8
fn C.sqlite3_column_int(&C.sqlite3_stmt, int) int
fn C.sqlite3_last_insert_rowid(&C.sqlite3) i64
fn C.sqlite3_bind_text(&C.sqlite3_stmt, int, voidptr, int, voidptr) int

pub const sqlite_ok = 0
pub const sqlite_row = 100
pub const sqlite_done = 101

// Row 代表查询结果的一行，names 存放列名，vals 存放每列的文本值。
pub struct Row {
pub mut:
	names []string
	vals  []string
}

// get_string 按列名获取字符串值，未命中返回空串。
pub fn (r &Row) get_string(col_name string) string {
	for i, name in r.names {
		if name == col_name {
			if i < r.vals.len {
				return r.vals[i]
			}
			return ''
		}
	}
	return ''
}

// get_int 按列名获取整数值，未命中返回 0。
pub fn (r &Row) get_int(col_name string) int {
	return r.get_string(col_name).int()
}

// SQLError 是 SQLite 操作返回的错误类型。
pub struct SQLError {
pub:
	msg  string
	code int
}

// msg 格式化错误信息。
pub fn (e SQLError) msg() string {
	return 'SQLite error: ${e.msg} (code: ${e.code})'
}

// DB 封装底层 SQLite 连接句柄。
pub struct DB {
mut:
	conn &C.sqlite3 = unsafe { nil }
pub mut:
	is_open bool
}

// connect 打开 path 处的 SQLite 数据库文件（或 ':memory:'）。
pub fn connect(path string) !DB {
	mut db := &C.sqlite3(unsafe { nil })
	code := C.sqlite3_open(path.str, &db)
	if code != sqlite_ok {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db))) }
		return error(msg)
	}
	return DB{
		conn:    db
		is_open: true
	}
}

// close 关闭数据库连接。
pub fn (mut db DB) close() ! {
	if !db.is_open || db.conn == unsafe { nil } {
		return
	}
	code := C.sqlite3_close(db.conn)
	if code != sqlite_ok {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
		return error(msg)
	}
	db.is_open = false
}

// last_insert_rowid 返回最近一次 INSERT 语句生成的 rowid。
pub fn (db &DB) last_insert_rowid() i64 {
	return C.sqlite3_last_insert_rowid(db.conn)
}

// q_int 执行查询并返回首行第一列的整数值。
pub fn (db &DB) q_int(query string) !int {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	code := C.sqlite3_prepare_v2(db.conn, &char(query.str), query.len, &stmt, unsafe { nil })
	if code != sqlite_ok {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
		return error('${msg} (${query})')
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	step_res := C.sqlite3_step(stmt)
	if step_res != sqlite_row {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
		return error('${msg} (${query})')
	}
	return C.sqlite3_column_int(stmt, 0)
}

// exec_none 执行 SQL 并返回状态码，无需返回结果集。
pub fn (db &DB) exec_none(query string) int {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	code := C.sqlite3_prepare_v2(db.conn, &char(query.str), query.len, &stmt, unsafe { nil })
	if code != sqlite_ok {
		return -1
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	return C.sqlite3_step(stmt)
}

// q_string 执行查询并返回首行第一列的字符串值。
pub fn (db &DB) q_string(query string) !string {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	code := C.sqlite3_prepare_v2(db.conn, &char(query.str), query.len, &stmt, unsafe { nil })
	if code != sqlite_ok {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
		return error('${msg} (${query})')
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	step_res := C.sqlite3_step(stmt)
	if step_res != sqlite_row {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
		return error('${msg} (${query})')
	}
	val := unsafe { &u8(C.sqlite3_column_text(stmt, 0)) }
	return if val != &u8(unsafe { nil }) { unsafe { tos_clone(val) } } else { '' }
}

// exec 执行无参 SQL 并返回所有结果行。
pub fn (db &DB) exec(query string) ![]Row {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	code := C.sqlite3_prepare_v2(db.conn, &char(query.str), query.len, &stmt, unsafe { nil })
	if code != sqlite_ok {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
		return error('${msg} (${query})')
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	nr_cols := C.sqlite3_column_count(stmt)
	mut col_names := []string{cap: nr_cols}
	for i in 0 .. nr_cols {
		col_char := unsafe { &u8(C.sqlite3_column_name(stmt, i)) }
		col_names << if col_char != unsafe { nil } { unsafe { tos_clone(col_char) } } else { '' }
	}
	mut rows := []Row{}
	for {
		res := C.sqlite3_step(stmt)
		if res != sqlite_row {
			break
		}
		mut row := Row{
			names: col_names
		}
		for i in 0 .. nr_cols {
			val := unsafe { &u8(C.sqlite3_column_text(stmt, i)) }
			if val == unsafe { nil } {
				row.vals << ''
			} else {
				row.vals << unsafe { tos_clone(val) }
			}
		}
		rows << row
	}
	return rows
}

// exec_param_many 使用位置参数 (?) 执行参数化 SQL 并返回结果行。
pub fn (db &DB) exec_param_many(query string, params []string) ![]Row {
	mut stmt := &C.sqlite3_stmt(unsafe { nil })
	mut code := C.sqlite3_prepare_v2(db.conn, &char(query.str), -1, &stmt, unsafe { nil })
	if code != sqlite_ok {
		msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
		return error('${msg} (${query})')
	}
	defer {
		C.sqlite3_finalize(stmt)
	}
	for i, param in params {
		code = C.sqlite3_bind_text(stmt, i + 1, voidptr(param.str), param.len, unsafe { nil })
		if code != sqlite_ok {
			msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
			return error('${msg} (${query})')
		}
	}
	nr_cols := C.sqlite3_column_count(stmt)
	mut col_names := []string{cap: nr_cols}
	for i in 0 .. nr_cols {
		col_char := unsafe { &u8(C.sqlite3_column_name(stmt, i)) }
		col_names << if col_char != unsafe { nil } { unsafe { tos_clone(col_char) } } else { '' }
	}
	mut rows := []Row{}
	for {
		res := C.sqlite3_step(stmt)
		if res == sqlite_done {
			break
		}
		if res != sqlite_row {
			msg := unsafe { cstring_to_vstring(&char(C.sqlite3_errmsg(db.conn))) }
			return error('${msg} (${query})')
		}
		mut row := Row{
			names: col_names
		}
		for i in 0 .. nr_cols {
			val := unsafe { &u8(C.sqlite3_column_text(stmt, i)) }
			if val == unsafe { nil } {
				row.vals << ''
			} else {
				row.vals << unsafe { tos_clone(val) }
			}
		}
		rows << row
	}
	return rows
}
