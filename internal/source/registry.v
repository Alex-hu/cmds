module source

// all_sources 按归因轮询顺序（priority 升序）构造全部已注册来源。
// ManualSource 是兜底源，需要其余源的 roots 来计算自己的 roots，因此最后构造。
pub fn all_sources() []Source {
	mut srcs := []Source{cap: 9}
	srcs << new_npm_source()
	srcs << new_brew_source()
	srcs << new_conda_source()
	srcs << new_cargo_source()
	srcs << new_go_source()
	srcs << new_rvm_source()
	srcs << new_app_source_auto()
	srcs << new_system_source()
	mut taken := []string{}
	for src in srcs {
		taken << src.roots()
	}
	srcs << new_manual_source_auto(taken)
	srcs.sort_with_compare(fn (a &Source, b &Source) int {
		if a.priority() < b.priority() {
			return -1
		}
		if a.priority() > b.priority() {
			return 1
		}
		return 0
	})
	return srcs
}
