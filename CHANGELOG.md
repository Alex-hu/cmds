# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-11-05

### Added
- TUI 详情浮层按 Enter（或 c/y）将完整执行命令复制到剪贴板，按 Esc/q 退出
- 纯函数 `model.execution_command` 支持环境判断：已在当前 PATH 的直接返回命令名；未在当前 PATH 时智能组合环境激活命令（支持 Conda、fnm、nvm、uv、Go GOPATH、RVM）或绝对路径
- 新增 `internal/clip` 跨平台剪贴板支持模块（macOS pbcopy、Windows clip.exe、Linux wl-copy/xclip/xsel 及终端 OSC 52 转义序列）
- 列表底部状态栏显示复制反馈提示（`✓ 已复制: ...`），按任意导航键自动恢复常规按键提示
- CI/CD 支持从 `CHANGELOG.md` 提取版本更新日志并挂载至 GitHub Release

## [0.1.0] - 2026-10-13

### Added
- 初版发布：支持三级分类模型（Ecosystem / Manager / Scope）
- Nushell 风格终端 TUI 交互式浏览（多级 Tab 联动、横向滑动视口、分页检索）
- 基于 SQLite 的本地命令快速索引与缓存
- 子命令系统：`cmds list`、`cmds update`、`cmds search`、`cmds version`
- macOS 双架构预编译构建（arm64 / x86_64 / universal）及一键安装脚本
