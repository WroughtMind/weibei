#!/usr/bin/env bash
set -euo pipefail

code=false
agent=false
editor=false
data_safety=false
release=false
tools=false
website=false

classify_path() {
  local path="$1"

  # 官网、检查编排和普通文档不改变 App；打包输入与工具分别判断。
  case "$path" in
    website/*|.github/workflows/pages.yml|script/check_website.sh)
      website=true
      return ;;
    .github/workflows/pr-checks.yml|script/ci_changed_scopes.sh|script/check_ci_routing.py)
      return ;;
  esac

  case "$path" in
    Sources/*|Tests/*|App/Sources/*|App/WindowBridge/*|App/project.yml|App/WeiBei.xcodeproj/*|Package.swift|Package.resolved|package.json|package-lock.json|Config/*)
      code=true ;;
  esac

  case "$path" in
    Sources/WeiBeiCore/AgentResources/*|Sources/WeiBeiCore/NativeAgentRuntime/*|Sources/WeiBeiCore/StudyAgentRuntime.swift|Sources/WeiBeiCore/Agent*|Sources/WeiBei/Views/NotesAgentView.swift|Sources/WeiBeiNativeCheck/*|package.json|package-lock.json)
      agent=true
      ;;
  esac

  case "$path" in
    Sources/WeiBei/WebEditor/*|Sources/WeiBei/Resources/Editor/*|Sources/WeiBeiWebEditorCheck/*|Sources/WeiBei/Support/AgentChatKaTeXMarkdown.swift|Sources/WeiBei/Views/*Markdown*|Sources/WeiBei/Views/NotesAgentView.swift|Sources/WeiBeiCore/Markdown*.swift|package.json|package-lock.json|tsconfig.editor.json|script/build_editor.mjs|script/convert_editor_fonts.py|script/editor-font-requirements.txt|DesignSystem/assets/fonts/*.ttf)
      editor=true
      ;;
  esac

  case "$path" in
    Sources/WeiBei/Stores/CourseProjectRootSupport.swift|Sources/WeiBei/Views/*Sidebar*.swift|Sources/WeiBei/Views/CourseDrawerHost.swift|Sources/WeiBei/Views/CourseImmersiveDrawerView.swift|Tests/WeiBeiSafetyTests/*|Sources/WeiBeiCore/CourseDocumentSearchIndex.swift|Sources/WeiBeiCore/CourseLibraryModels.swift|Sources/WeiBeiCore/LearningModels.swift|Sources/WeiBeiCore/NoteSourceRelations.swift|Sources/WeiBeiCore/WorkspaceModels.swift)
      data_safety=true
      ;;
  esac

  # Shared roots cannot be classified safely from the path alone.
  case "$path" in
    Sources/WeiBei/Stores/WorkspaceStore.swift|App/Sources/AppDelegate.swift|Sources/WeiBei/Views/ContentView.swift|Sources/WeiBei/Views/StableDocumentWorkspace.swift|Sources/WeiBeiSelfCheck/main.swift|Package.swift|Package.resolved)
      agent=true
      editor=true
      data_safety=true
      ;;
  esac

  case "$path" in
    VERSION|Package.swift|Package.resolved|package.json|package-lock.json|.github/workflows/release.yml|App/project.yml|App/WeiBei.xcodeproj/*|App/Config/*|App/Resources/*|App/script/*|script/verify_app_launch.sh|script/package_size.py|script/build_number.py|script/check_build_number.py|script/check_build_info.swift|script/build_and_run.sh|script/build_release_dmg.sh|script/dmg/*|Sources/WeiBeiDev/*|PRIVACY.md|THIRD_PARTY_NOTICES.md|ASSET_ATTRIBUTIONS.md|DesignSystem/assets/app-icon/*|DesignSystem/assets/dmg/*|DesignSystem/scripts/*|Config/*|*.entitlements|*/Info.plist)
      release=true
      ;;
  esac

  # Node 工具脚本类型检查（npm run typecheck:tools 的触发面）。
  # 根 tsconfig.json 的 include 覆盖 DesignSystem/scripts;package.json/lockfile 变化
  # 可能改动 typescript/@types/node 版本或 typecheck:tools 本身，也必须触发。
  case "$path" in
    script/*.ts|script/homebrew/*.mjs|DesignSystem/scripts/*.ts|tsconfig.json|package.json|package-lock.json)
      tools=true
      ;;
  esac
}

emit_scopes() {
  local scope
  for scope in code agent editor data_safety release tools website; do
    printf '%s=%s\n' "$scope" "${!scope}"
  done
}

expect_scopes() {
  local expected="$1" path scope actual=""
  shift
  code=false agent=false editor=false data_safety=false release=false tools=false website=false
  for path in "$@"; do classify_path "$path"; done
  for scope in code agent editor data_safety release tools website; do
    if [[ "${!scope}" == true ]]; then actual="${actual}${actual:+ }$scope"; fi
  done
  if [[ "$actual" != "$expected" ]]; then
    echo "scope self-check failed for $*: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--self-check" ]]; then
  expect_scopes "website" "website/index.html" ".github/workflows/pages.yml" "script/check_website.sh"
  expect_scopes "" ".github/workflows/pr-checks.yml" "script/ci_changed_scopes.sh" "script/check_ci_routing.py"
  expect_scopes "" "Docs/plans/example.md" "Docs/releases/README.md" "DesignSystem/README.md" "LICENSE"
  expect_scopes "code agent editor data_safety website" ".github/workflows/pages.yml" "Sources/WeiBei/Stores/WorkspaceStore.swift"
  expect_scopes "release" ".github/workflows/release.yml" "script/build_release_dmg.sh" "PRIVACY.md"
  expect_scopes "code agent editor data_safety" "Sources/WeiBei/Stores/WorkspaceStore.swift"
  expect_scopes "code editor" "Sources/WeiBei/WebEditor/src/editor.ts" "Sources/WeiBeiCore/MarkdownAttachmentStore.swift"
  expect_scopes "editor" "tsconfig.editor.json" "script/build_editor.mjs"
  expect_scopes "code data_safety" "Tests/WeiBeiSafetyTests/CourseProjectRootSelfCheck.swift"
  expect_scopes "code data_safety" "Sources/WeiBei/Views/SidebarView.swift" "Sources/WeiBei/Views/CourseDrawerHost.swift"
  expect_scopes "code data_safety" "Sources/WeiBeiCore/LearningModels.swift" "Sources/WeiBeiCore/CourseDocumentSearchIndex.swift" "Sources/WeiBeiCore/NoteSourceRelations.swift"
  expect_scopes "code agent" "Sources/WeiBeiCore/NativeAgentRuntime/NativeAgentLoop.swift"
  expect_scopes "code" "App/Sources/ConversationController.swift" "App/WindowBridge/NativeWindowBridge.swift"
  expect_scopes "code agent editor data_safety" "App/Sources/AppDelegate.swift"
  expect_scopes "code release" "App/project.yml"
  expect_scopes "release" "App/Resources/Web/diagram.html" "App/script/check-ci.sh"
  expect_scopes "tools" "script/check-genui-math.ts" "tsconfig.json" "script/homebrew/generate_cask.test.mjs"
  expect_scopes "release tools" "DesignSystem/scripts/build-icns.ts"
  expect_scopes "code agent editor release tools" "package.json" "package-lock.json"
  echo "CI scope self-check passed"
  exit 0
fi

if (( $# != 2 )); then
  echo "usage: $0 <base-sha> <head-sha> | --self-check" >&2
  exit 2
fi

while IFS= read -r -d '' path; do
  classify_path "$path"
done < <(git diff --name-only -z "$1" "$2")

emit_scopes
