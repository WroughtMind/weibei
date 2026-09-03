# 魏碑开发入口（薄转发，只转发不复制逻辑；细节见各脚本与 README）
# 用法：make <target>，或 make help 查看全部目标。

.PHONY: help build run check package verify editor-build genui-math-check perf-p95 release-community release-notarized clean

help: ## 列出全部目标与一句话说明（默认目标）
	@echo "魏碑 Makefile 入口："
	@echo "  make build               Swift 构建（swift build）"
	@echo "  make run                 构建并启动 App（./script/build_and_run.sh）"
	@echo "  make check               构建 + 全部自检（./script/build_and_run.sh check）"
	@echo "  make package             为当前 Mac 架构生成 dist/魏碑.app 候选包"
	@echo "  make verify              打包、启动并确认当前架构 App 可运行后退出"
	@echo "  make editor-build        esbuild 构建 Web 编辑器（npm run build:editor）"
	@echo "  make genui-math-check    校验 GenUI 安全数学表达式运行时（npx tsx script/check-genui-math.ts）"
	@echo "  make perf-p95            p95 性能解析，用法：make perf-p95 LOG=<perf-log> METRIC=<metric-name>"
	@echo "  make release-community   为当前 Mac 架构构建社区版 DMG"
	@echo "  make release-notarized   为当前 Mac 架构构建并公证 DMG（受签名与公证变量约束）"
	@echo "  make clean               清理构建产物（swift package clean && rm -rf dist；不删 node_modules / 用户数据）"

build: ## Swift 构建
	swift build

run: ## 构建并启动 App
	./script/build_and_run.sh

check: ## 构建 + 全部自检
	./script/build_and_run.sh check

package: ## 生成 dist/魏碑.app 候选包
	./script/build_and_run.sh package

verify: ## 打包并完成一次真实进程启动验收
	./script/build_and_run.sh verify

editor-build: ## esbuild 构建 Web 编辑器
	npm run build:editor
genui-math-check: ## 校验 GenUI 安全数学表达式运行时
	npx tsx script/check-genui-math.ts

perf-p95: ## p95 性能解析：make perf-p95 LOG=<perf-log> METRIC=<metric-name>
	@if [ -z "$(LOG)" ] || [ -z "$(METRIC)" ]; then \
		echo "usage: make perf-p95 LOG=<perf-log> METRIC=<metric-name>" >&2; \
		exit 2; \
	fi
	./script/perf_p95.sh $(LOG) $(METRIC)

release-community: ## 构建社区版 DMG
	./script/build_release_dmg.sh --community

release-notarized: ## 构建并公证 DMG（受 WEIBEI_CODESIGN_IDENTITY / WEIBEI_NOTARY_KEYCHAIN_PROFILE 约束）
	./script/build_release_dmg.sh --notarized

clean: ## 清理构建产物（不删 node_modules / 用户数据）
	swift package clean
	rm -rf dist
