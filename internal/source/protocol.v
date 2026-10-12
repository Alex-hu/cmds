module source

import internal.model

// Scope 是三级分类：conda 的各环境、fnm/nvm 的各 node 版本。id 作为过滤键与 UI tab 键。
pub struct Scope {
pub:
	id    string // 例: 'v24.11.1'、'base'、'miniforge3/envs/ml'
	label string // 展示名
}

// Attribution 是归因结果：realpath 属于本源时返回，不属于返回 none。
pub struct Attribution {
pub:
	source_id string // 发现本条目的 Source 插件 id (用于路由到对应的 enrich)
	ecosystem string // 一级生态: 'node', 'python', 'go', 'rust', 'brew', 'system', 'app', 'manual'
	manager   string // 二级管理器: 'fnm', 'nvm', 'pnpm', 'conda', 'cargo', 'brew', 'system'
	scope     string // 三级分类键；空串=无子分类
	origin    string // 精确来源标签，例: 'conda:miniforge3/envs/ml'、'fnm:v24.11.1'
}

// Source 是每种命令来源的插件协议（签名均已在 V 0.5.2 实测编译通过）。
// 新增来源 = 实现本接口 + 在 registry 注册，核心管道与 UI 零改动。
pub interface Source {
	// ecosystem 返回所属的一级技术栈生态。
	ecosystem() string
	// id 返回插件/管理器唯一标识。
	id() string
	// label 返回展示名。
	label() string
	// roots 返回本源的全部发现根（绝对路径目录）。
	// 反映"机器上装了什么"，不要求当前激活（fnm 未激活版本、conda 各环境都在此列）。
	roots() []string
	// attribute 判断 realpath 是否属于本源；不属于返回 none。
	// 归因轮询按 priority 升序，首个返回 Attribution 的源胜出。
	attribute(realpath string) ?Attribution
	// enrich 就地填充本源 entry 的 version/description/installed_at。
	// 只读文件系统元数据与各源自有注册表，不执行被索引的二进制；失败记 warning 不中断。
	enrich(mut entries []model.Entry) !
	// scopes 返回三级分类列表（conda→环境、fnm→node 版本）；无子分类返回空数组。
	scopes() []Scope
	// priority 越小越先轮询：具体的源在前，兜底源（system/manual）在后。
	priority() int
}
