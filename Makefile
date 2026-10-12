# cmds — 自动化构建与依赖管理

.PHONY: all check-deps deps build prod test fmt vet clean help

all: prod

# 检查系统级前置依赖
check-deps:
	@which v >/dev/null 2>&1 || (echo "错误: 未找到 v 编译器，请先安装 V 语言 (https://vlang.io)" && exit 1)

# 同步与还原 v.mod 中声明的第三方依赖（类似 mvn dependency:resolve）
deps:
	@echo "同步第三方依赖 (v.mod)..."
	v sync

# 调试构建
build: check-deps
	v -o cmds .

# 发布构建（带 -prod 优化）
prod: check-deps
	v -prod -o cmds .

# 运行测试
test: check-deps
	v test .

# 代码格式化
fmt:
	v fmt -w .

# 静态检查
vet:
	v vet .

# 清理产物与编译临时目录
clean:
	@echo "清理二进制产物与编译临时文件..."
	@rm -rf cmds
	@find . -maxdepth 1 \( -name ".*v3*" -o -name "..v3*" \) -exec rm -rf {} + 2>/dev/null || true

help:
	@echo "可用指令:"
	@echo "  make prod        发布构建（默认）"
	@echo "  make build       调试构建"
	@echo "  make test        运行所有测试"
	@echo "  make deps        安装/同步 v.mod 中的第三方依赖 (v sync)"
	@echo "  make check-deps  检查本机环境与系统工具依赖"
	@echo "  make fmt         格式化代码"
	@echo "  make vet         静态代码检查"
	@echo "  make clean       清理二进制产物与编译临时文件"
