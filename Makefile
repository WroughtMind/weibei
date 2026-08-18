# 魏碑开发入口（薄转发，只转发不复制逻辑；细节见各脚本与 README）
# 用法：make <target>，或 make help 查看全部目标。

.PHONY: help build run check package editor-build rich-answer-build genui-math-check perf-p95 pi-prepare release-community release-notarized clean

help: ## 列出全部目标与一句话说明（默认目标）
	@echo "魏碑 Makefile 入口："
	@echo "  make build               Swift 构建（swift build）"
	@echo "  make run                 构建并启动 App（./script/build_and_run.sh）"
	@echo "  make check               构建 + 全部自检（./script/build_and_run.sh check）"
	@echo "  make package             生成 dist/魏碑.app 候选包（./script/build_and_run.sh package）"
	@echo "  make editor-build        esbuild 构建 Web 编辑器（npm run build:editor）"
	@echo "  make rich-answer-build   构建并嵌入富回答运行时（npm -w Prototypes/RichAnswerWebRuntime run build:embed）"
	@echo "  make genui-math-check    校验 GenUI 安全数学表达式运行时（npx tsx script/check-genui-math.ts）"
	@echo "  make perf-p95            p95 性能解析，用法：make perf-p95 LOG=<perf-log> METRIC=<metric-name>"
	@echo "  make pi-prepare          准备 Pi 运行时（./script/prepare_pi_runtime.sh）"
	@echo "  make release-community   构建社区版 DMG（./script/build_release_dmg.sh --community）"
	@echo "  make release-notarized   构建并公证 DMG（受 WEIBEI_CODESIGN_IDENTITY / WEIBEI_NOTARY_KEYCHAIN_PROFILE 约束）"
	@echo "  make clean               清理构建产物（swift package clean && rm -rf dist；不删 node_modules / .build/pi-runtime / 用户数据）"

build: ## Swift 构建
	swift build

run: ## 构建并启动 App
	./script/build_and_run.sh

check: ## 构建 + 全部自检
	./script/build_and_run.sh check

package: ## 生成 dist/魏碑.app 候选包
	./script/build_and_run.sh package

editor-build: ## esbuild 构建 Web 编辑器
	npm run build:editor

rich-answer-build: ## 构建并嵌入富回答运行时
	npm -w Prototypes/RichAnswerWebRuntime run build:embed

genui-math-check: ## 校验 GenUI 安全数学表达式运行时
	npx tsx script/check-genui-math.ts

perf-p95: ## p95 性能解析：make perf-p95 LOG=<perf-log> METRIC=<metric-name>
	@if [ -z "$(LOG)" ] || [ -z "$(METRIC)" ]; then \
		echo "usage: make perf-p95 LOG=<perf-log> METRIC=<metric-name>" >&2; \
		exit 2; \
	fi
	./script/perf_p95.sh $(LOG) $(METRIC)

pi-prepare: ## 准备 Pi 运行时
	./script/prepare_pi_runtime.sh

release-community: ## 构建社区版 DMG
	./script/build_release_dmg.sh --community

release-notarized: ## 构建并公证 DMG（受 WEIBEI_CODESIGN_IDENTITY / WEIBEI_NOTARY_KEYCHAIN_PROFILE 约束）
	./script/build_release_dmg.sh --notarized

clean: ## 清理构建产物（不删 node_modules / .build/pi-runtime / 用户数据）
	@if [ -d .build/pi-runtime ]; then \
		keep="$${TMPDIR:-/tmp}/weibei-pi-runtime-clean-keep-$$$$"; \
		mv .build/pi-runtime "$$keep"; \
		swift package clean; \
		mkdir -p .build; \
		mv "$$keep" .build/pi-runtime; \
	else \
		swift package clean; \
	fi
	rm -rf dist
