module model

// Entry 是索引的最小单元：一个 (name, realpath) 唯一确定一个 Entry。
pub struct Entry {
pub mut:
	name         string
	source       string // system|brew|npm|conda|cargo|go|rvm|app|manual
	origin       string // 例: conda:miniforge3/envs/ml / npm@fnm/v22.12.0
	scope        string // 二级分类键（conda 环境、node 版本标识）；空串=无
	realpath     string
	occurrences  []Occurrence
	in_path      bool // 管理器根目录发现但当前不在 PATH 中时为 false
	version      string
	description  string
	installed_at string // 'YYYY-MM-DD HH:mm'，近似值
	size_bytes   u64
	kind         string // binary|script
}

// Occurrence 记录同一文件在 PATH 中的每次出现，用于遮蔽分析。
pub struct Occurrence {
pub:
	path          string
	path_priority int // 越小越靠前（越优先生效）
}

// MergedEntry 是展示层视图：同名命令的全部提供者。
pub struct MergedEntry {
pub:
	name      string
	providers []Entry
}

// dedupe 按 (name, realpath) 合并 Entry，occurrences 并集后按优先级排序。
pub fn dedupe(entries []Entry) []Entry {
	mut out := []Entry{}
	mut idx := map[string]int{}
	for e in entries {
		key := '${e.name}|${e.realpath}'
		if key in idx {
			mut merged := out[idx[key]]
			merged.occurrences << e.occurrences
			if e.in_path {
				merged.in_path = true
			}
			sort_occurrences(mut merged.occurrences)
			out[idx[key]] = merged
		} else {
			mut first := e
			sort_occurrences(mut first.occurrences)
			idx[key] = out.len
			out << first
		}
	}
	return out
}

fn sort_occurrences(mut occs []Occurrence) {
	occs.sort_with_compare(fn (a &Occurrence, b &Occurrence) int {
		if a.path_priority < b.path_priority {
			return -1
		}
		if a.path_priority > b.path_priority {
			return 1
		}
		return 0
	})
}

// merge_by_name 把 Entry 列表按 name 聚合成展示视图（保持首次出现顺序）。
pub fn merge_by_name(entries []Entry) []MergedEntry {
	mut order := []string{}
	mut by := map[string][]Entry{}
	for e in entries {
		if e.name !in by {
			order << e.name
		}
		by[e.name] << e
	}
	mut out := []MergedEntry{cap: order.len}
	for name in order {
		out << MergedEntry{ name: name, providers: by[name] }
	}
	return out
}

// filter_by_source 按 source 过滤；source 为空串时返回全部。
pub fn filter_by_source(entries []Entry, source string) []Entry {
	if source == '' {
		return entries
	}
	return entries.filter(it.source == source)
}

// filter_by_scope 按 scope 过滤；scope 为空串时返回全部。
pub fn filter_by_scope(entries []Entry, scope string) []Entry {
	if scope == '' {
		return entries
	}
	return entries.filter(it.scope == scope)
}

// filter_by_text 对 name/description/origin 做不区分大小写的包含匹配。
pub fn filter_by_text(entries []Entry, q string) []Entry {
	if q == '' {
		return entries
	}
	lq := q.to_lower()
	return entries.filter(it.name.to_lower().contains(lq)
		|| it.description.to_lower().contains(lq) || it.origin.to_lower().contains(lq))
}

// fuzzy_score 做 fzf 式子序列打分：命中返回分数（越大越优），不匹配返回 none。
// 记分：每字符 1 分，连续命中 +10，词首（前一字符非字母数字）+15，首字符命中 +20。
pub fn fuzzy_score(needle string, hay string) ?int {
	if needle == '' {
		return 0
	}
	n := needle.to_lower()
	h := hay.to_lower()
	mut score := 0
	mut pi := 0
	mut prev := -2
	for ch in n {
		found := h.index_after(ch.ascii_str(), pi) or { return none }
		score += 1
		if found == prev + 1 {
			score += 10
		}
		if found == 0 {
			score += 20
		} else {
			before := h[found - 1]
			if !before.is_alnum() {
				score += 15
			}
		}
		prev = found
		pi = found + 1
	}
	return score
}
