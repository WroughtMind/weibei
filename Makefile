.PHONY: run check verify package prepare prepare-web-editor prepare-pi-runtime clean-generated

# 构建临时应用并使用默认模式启动。
run:
	swift run WeiBeiDevTool run

# Swift 检查会在 fresh clone 中准备锁定依赖；随后执行 TypeScript 质量门。
check:
	swift run WeiBeiDevTool check
	npm run check

# 构建临时应用并运行默认验收场景。
verify:
	swift run WeiBeiDevTool verify

# 事务化生成并校验本地应用包。
package:
	swift run WeiBeiDevTool package

# 准备全部生成资源和锁定的 PI runtime。
prepare:
	swift run WeiBeiDevTool prepare all

# 准备 Node 依赖并生成应用内 Web 资源。
prepare-web-editor:
	swift run WeiBeiDevTool prepare web-editor

# 下载或复用并校验锁定的 PI runtime。
prepare-pi-runtime:
	swift run WeiBeiDevTool prepare pi-runtime

# 删除由 TypeScript 构建生成且可重建的资源。
clean-generated:
	npm run clean:generated
