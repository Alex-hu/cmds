module model

// Entry 是索引的最小单元：一个 (name, realpath) 唯一确定一个 Entry。
pub struct Entry {
pub mut:
	name         string
	source_id    string // 负责发现与富化该条目的 Source 插件 id (如 'npm', 'pnpm', 'conda')
	ecosystem    string // 一级技术栈 (node|python|go|rust|brew|system|app|manual|ruby)
	manager      string // 二级包/环境管理器 (fnm|nvm|pnpm|conda|cargo|go|brew|system|app|manual|rvm)
	scope        string // 三级环境/版本标识；空串=无独立环境
	origin       string // 例: conda:miniforge3/envs/ml / fnm:v22.12.0
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

// filter_by_ecosystem 按 ecosystem 过滤；ecosystem 为空串或 'all' 时返回全部。
pub fn filter_by_ecosystem(entries []Entry, eco string) []Entry {
	if eco == '' || eco == 'all' {
		return entries
	}
	return entries.filter(it.ecosystem == eco)
}

// filter_by_manager 按 manager 过滤；manager 为空串或 'all' 时返回全部。
pub fn filter_by_manager(entries []Entry, mgr string) []Entry {
	if mgr == '' || mgr == 'all' {
		return entries
	}
	return entries.filter(it.manager == mgr)
}

// filter_by_scope 按 scope 过滤；scope 为空串或 'all' 时返回全部。
pub fn filter_by_scope(entries []Entry, scope string) []Entry {
	if scope == '' || scope == 'all' {
		return entries
	}
	return entries.filter(it.scope == scope)
}

// filter_by_source 兼容按来源过滤：匹配 ecosystem、manager 或 source_id。
pub fn filter_by_source(entries []Entry, source string) []Entry {
	if source == '' || source == 'all' {
		return entries
	}
	return entries.filter(it.ecosystem == source || it.manager == source || it.source_id == source)
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

// SearchResult 包装检索结果及面向 AI/用户的行动指引。
pub struct SearchResult {
pub:
	entry      Entry
	score      int
	how_to_run string
	switch_env string
}

// action_guidance 推导针对 AI/用户的直接执行路径与环境切换命令。
pub fn action_guidance(e Entry) (string, string) {
	how_to_run := if e.in_path { e.name } else { e.realpath }
	mut switch_env := ''
	if !e.in_path {
		if e.manager in ['anaconda3', 'miniforge3', 'miniconda3', 'conda'] && e.scope != '' {
			switch_env = 'conda activate ${e.scope}'
		} else if e.manager == 'fnm' && e.scope != '' {
			switch_env = 'fnm use ${e.scope}'
		} else if e.manager == 'nvm' && e.scope != '' {
			switch_env = 'nvm use ${e.scope}'
		} else if e.manager == 'uv' {
			switch_env = 'uv run ${e.name}'
		} else if e.manager == 'go' && e.scope == 'gopath' {
			switch_env = 'export PATH="\$GOPATH/bin:\$PATH"'
		}
	}
	return how_to_run, switch_env
}

// rank_search 对 entries 执行多词加权检索与排序，并返回带行动指引的结果列表。
pub fn rank_search(entries []Entry, query string) []SearchResult {
	trimmed := query.trim_space()
	if trimmed == '' {
		mut res := []SearchResult{cap: entries.len}
		for e in entries {
			htr, se := action_guidance(e)
			res << SearchResult{
				entry:      e
				score:      0
				how_to_run: htr
				switch_env: se
			}
		}
		return res
	}

	tokens := trimmed.to_lower().split(' ').filter(it != '')
	if tokens.len == 0 {
		return []SearchResult{}
	}

	// 1. 尝试 AND 匹配：每个 token 必须在条目的某些字段中出现
	mut and_candidates := []SearchResult{}
	mut or_candidates := []SearchResult{}

	for e in entries {
		name_l := e.name.to_lower()
		desc_l := e.description.to_lower()
		eco_l := e.ecosystem.to_lower()
		mgr_l := e.manager.to_lower()
		scope_l := e.scope.to_lower()
		path_l := e.realpath.to_lower()

		mut match_count := 0
		mut score := 0

		for tok in tokens {
			mut tok_matched := false
			if name_l == tok {
				score += 1000
				tok_matched = true
			} else if name_l.starts_with(tok) {
				score += 500
				tok_matched = true
			} else if name_l.contains(tok) {
				score += 200
				tok_matched = true
			}

			if desc_l.contains(tok) {
				score += 60
				tok_matched = true
			}
			if mgr_l == tok || scope_l == tok {
				score += 50
				tok_matched = true
			} else if mgr_l.contains(tok) || scope_l.contains(tok) || eco_l.contains(tok) {
				score += 30
				tok_matched = true
			}
			if path_l.contains(tok) {
				score += 20
				tok_matched = true
			}

			if tok_matched {
				match_count++
			}
		}

		if match_count > 0 {
			if e.in_path {
				score += 20
			}
			htr, se := action_guidance(e)
			sr := SearchResult{
				entry:      e
				score:      score
				how_to_run: htr
				switch_env: se
			}
			if match_count == tokens.len {
				and_candidates << sr
			} else {
				or_candidates << sr
			}
		}
	}

	mut final_list := if and_candidates.len > 0 { and_candidates } else { or_candidates }
	final_list.sort_with_compare(fn (a &SearchResult, b &SearchResult) int {
		if a.score > b.score {
			return -1
		}
		if a.score < b.score {
			return 1
		}
		if a.entry.name < b.entry.name {
			return -1
		}
		if a.entry.name > b.entry.name {
			return 1
		}
		return 0
	})
	return final_list
}
