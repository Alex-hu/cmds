// simple_sources.v —— 四个"简单来源"的 Source 实现：
// SystemSource（系统自带）、RvmSource（RVM）、AppSource（.app bundle 内）、
// ManualSource（兜底）。共同点是无需读管理器自有注册表：归因只做路径前缀/形状判断，
// enrich 全部 no-op（版本信息留待 M4 deep 探测统一补齐），scopes 全部为空。
module source

import os
import internal.model

// system_bin_dirs 是系统命令目录的固定候选清单；roots() 按实际存在过滤，
// attribute() 则始终按清单整体做前缀匹配（与目录当前是否存在无关）。
const system_bin_dirs = ['/bin', '/usr/bin', '/sbin', '/usr/sbin']!

// ---------------------------------------------------------------------------
// SystemSource：系统自带命令
// ---------------------------------------------------------------------------

// SystemSource 归因 macOS 系统自带命令（/bin、/usr/bin、/sbin、/usr/sbin）。
pub struct SystemSource {}

// new_system_source 构造系统源；目录发现延迟到 roots()/attribute() 内按固定候选清单进行。
pub fn new_system_source() SystemSource {
	return SystemSource{}
}

// id 返回源标识 'system'（一级 tab 键、Entry.source 取值）。
fn (s SystemSource) id() string {
	return 'system'
}

// label 返回展示名。
fn (s SystemSource) label() string {
	return '系统'
}

// roots 返回候选清单中本机实际存在的系统命令目录。
fn (s SystemSource) roots() []string {
	mut out := []string{}
	for d in system_bin_dirs {
		if os.is_dir(d) {
			out << d
		}
	}
	return out
}

// attribute 判断 realpath 是否位于四个系统命令目录之下；前缀必须整目录匹配
// （拼 '/bin/' 形式，避免 '/usr/binux' 之类误命中），不属于本源返回 none。
fn (s SystemSource) attribute(realpath string) ?Attribution {
	for d in system_bin_dirs {
		if realpath.starts_with(d + '/') {
			return Attribution{ source: 'system', origin: 'system', scope: '' }
		}
	}
	return none
}

// enrich 是 no-op：系统命令无自有注册表可读，版本信息留待 M4 deep 探测。
fn (s SystemSource) enrich(mut _ []model.Entry) ! {
}

// scopes 返回空数组：系统源无二级分类。
fn (s SystemSource) scopes() []Scope {
	return []
}

// priority 返回归因轮询优先级：排在 rvm/app 等具体源之后、manual 之前。
fn (s SystemSource) priority() int {
	return 100
}

// ---------------------------------------------------------------------------
// RvmSource：RVM（Ruby Version Manager）
// ---------------------------------------------------------------------------

// RvmSource 归因 RVM 安装的命令，发现根为 ~/.rvm/bin（存在时）。
pub struct RvmSource {
pub mut:
	root string // 发现根（绝对路径）；空串表示本机未安装 RVM
}

// new_rvm_source 按真实机器发现构造：~/.rvm/bin 存在才设为 root，否则 root 留空。
pub fn new_rvm_source() RvmSource {
	candidate := os.join_path(os.home_dir(), '.rvm', 'bin')
	if os.is_dir(candidate) {
		return RvmSource{ root: candidate }
	}
	return RvmSource{}
}

// id 返回源标识 'rvm'。
fn (s RvmSource) id() string {
	return 'rvm'
}

// label 返回展示名。
fn (s RvmSource) label() string {
	return 'rvm'
}

// roots 返回 [root]；本机未安装 RVM（root 为空）时返回空数组。
fn (s RvmSource) roots() []string {
	if s.root == '' {
		return []
	}
	return [s.root]
}

// attribute 判断 realpath 是否位于 root 目录之下（整目录前缀 'root/'），
// root 为空或前缀不匹配返回 none。
fn (s RvmSource) attribute(realpath string) ?Attribution {
	if s.root != '' && realpath.starts_with(s.root + '/') {
		return Attribution{ source: 'rvm', origin: 'rvm', scope: '' }
	}
	return none
}

// enrich 是 no-op：版本信息留待 M4 deep 探测。
fn (s RvmSource) enrich(mut _ []model.Entry) ! {
}

// scopes 返回空数组：RVM 源无二级分类。
fn (s RvmSource) scopes() []Scope {
	return []
}

// priority 返回归因轮询优先级：RVM 是具体源，先于 app/system/manual。
fn (s RvmSource) priority() int {
	return 60
}

// ---------------------------------------------------------------------------
// AppSource：.app bundle 内命令
// ---------------------------------------------------------------------------

// AppSource 归因位于 macOS .app bundle 内部的命令（PATH 目录路径含 '.app/Contents/'）。
pub struct AppSource {
pub mut:
	app_dirs []string // PATH 中位于 .app bundle 内且实际存在的目录（realpath 归一化、去重）
}

// new_app_source 从给定 PATH 环境变量串收集发现根：凡路径含 '.app/Contents/'
// 且实际存在的目录收为 root（realpath 归一化后去重）。
pub fn new_app_source(path_env string) AppSource {
	mut s := AppSource{}
	mut seen := map[string]bool{}
	for dir in path_env.split(':') {
		if dir == '' || !dir.contains('.app/Contents/') || !os.is_dir(dir) {
			continue
		}
		rp := os.real_path(dir)
		if rp in seen {
			continue
		}
		seen[rp] = true
		s.app_dirs << rp
	}
	return s
}

// new_app_source_auto 按真实机器的 PATH 环境变量发现 .app bundle 内目录。
pub fn new_app_source_auto() AppSource {
	return new_app_source(os.getenv('PATH'))
}

// id 返回源标识 'app'。
fn (s AppSource) id() string {
	return 'app'
}

// label 返回展示名。
fn (s AppSource) label() string {
	return 'app'
}

// roots 返回收集到的 .app bundle 内目录。
fn (s AppSource) roots() []string {
	return s.app_dirs
}

// attribute 判断 realpath 是否位于某个 .app bundle 内：路径含 '.app/Contents/'
// 即命中，origin 取紧邻 Contents 之前、以 '.app' 结尾的那段路径的 bundle 名
// （去掉 '.app' 后缀），例: '/Applications/Fake.app/Contents/MacOS/tools/x'
// → origin 'app:Fake'。不含该形状返回 none。
fn (s AppSource) attribute(realpath string) ?Attribution {
	if !realpath.contains('.app/Contents/') {
		return none
	}
	parts := realpath.split('/')
	mut bundle := ''
	for i in 0 .. parts.len - 1 {
		if parts[i + 1] == 'Contents' && parts[i].ends_with('.app') {
			// 多层嵌套时取最内层（最后一次命中）
			bundle = parts[i]
		}
	}
	if bundle == '' {
		return none
	}
	name := bundle[..bundle.len - 4] // 去掉 '.app' 后缀（4 字符）
	return Attribution{ source: 'app', origin: 'app:' + name, scope: '' }
}

// enrich 是 no-op：版本信息留待 M4 deep 探测。
fn (s AppSource) enrich(mut _ []model.Entry) ! {
}

// scopes 返回空数组：app 源无二级分类。
fn (s AppSource) scopes() []Scope {
	return []
}

// priority 返回归因轮询优先级：app 是具体源，先于 system/manual。
fn (s AppSource) priority() int {
	return 70
}

// ---------------------------------------------------------------------------
// ManualSource：兜底源
// ---------------------------------------------------------------------------

// ManualSource 是兜底源：PATH 中无法归因到任何具体源的目录归此管理。
// attribute 永远返回 none——兜底不在归因轮询中"胜出"，而是由 update 管道在
// 全部源轮询结束后把剩余未归因条目统一标记为 manual（见 ARCHITECTURE.md §3）。
pub struct ManualSource {
pub mut:
	root_dirs []string // 过滤后的 PATH 目录（realpath 归一化、去重）
}

// new_manual_source 从给定 PATH 串收集兜底目录：目录需实际存在，且目录串与
// realpath(os.real_path) 都未被其他源占用（taken）；以 realpath 为键去重——
// 覆盖 /usr/local/bin 符号链接到别处、同一目录以不同路径串重复出现的场景。
pub fn new_manual_source(path_env string, taken []string) ManualSource {
	mut m := ManualSource{}
	mut taken_set := map[string]bool{}
	for t in taken {
		taken_set[t] = true
	}
	mut seen := map[string]bool{}
	for dir in path_env.split(':') {
		if dir == '' || !os.is_dir(dir) {
			continue
		}
		if dir in taken_set {
			continue
		}
		rp := os.real_path(dir)
		if rp in taken_set || rp in seen {
			continue
		}
		seen[dir] = true
		seen[rp] = true
		m.root_dirs << rp
	}
	return m
}

// new_manual_source_auto 按真实机器的 PATH 构造兜底源；taken 为其他源已占用的目录清单。
pub fn new_manual_source_auto(taken []string) ManualSource {
	return new_manual_source(os.getenv('PATH'), taken)
}

// id 返回源标识 'manual'。
fn (m ManualSource) id() string {
	return 'manual'
}

// label 返回展示名。
fn (m ManualSource) label() string {
	return 'manual'
}

// roots 返回过滤后的兜底目录。
fn (m ManualSource) roots() []string {
	return m.root_dirs
}

// attribute 永远返回 none：兜底归因由 update 管道在全部源轮询结束后统一处理，
// 本源不参与轮询竞争（否则 priority 999 的兜底源永远轮不到）。
fn (m ManualSource) attribute(_ string) ?Attribution {
	return none
}

// enrich 是 no-op：版本信息留待 M4 deep 探测。
fn (m ManualSource) enrich(mut _ []model.Entry) ! {
}

// scopes 返回空数组：兜底源无二级分类。
fn (m ManualSource) scopes() []Scope {
	return []
}

// priority 返回归因轮询优先级：999，排在所有具体源之后，兜底。
fn (m ManualSource) priority() int {
	return 999
}
