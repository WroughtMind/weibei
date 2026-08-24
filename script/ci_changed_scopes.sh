#!/usr/bin/env bash
set -euo pipefail

code=false
agent=false
editor=false
data_safety=false
release=false
tools=false

classify_path() {
  local path="$1"

  case "$path" in
    Sources/*|Tests/*|Package.swift|Package.resolved|package.json|package-lock.json|script/*|.github/workflows/*|VERSION|DesignSystem/*|Config/*)
      code=true
      ;;
  esac

  case "$path" in
    Sources/WeiBeiCore/AgentResources/*|Sources/WeiBeiCore/NativeAgentRuntime/*|Sources/WeiBeiCore/StudyAgentRuntime.swift|Sources/WeiBeiCore/Agent*|Sources/WeiBei/Views/NotesAgentView.swift|Sources/WeiBeiNativeCheck/*|package.json|package-lock.json)
      agent=true
      ;;
  esac

  case "$path" in
    Sources/WeiBei/WebEditor/*|Sources/WeiBei/Resources/Editor/*|Sources/WeiBeiWebEditorCheck/*|Sources/WeiBei/Support/AgentChatKaTeXMarkdown.swift|Sources/WeiBei/Views/*Markdown*|Sources/WeiBei/Views/NotesAgentView.swift|Sources/WeiBeiCore/Markdown*.swift|package.json|package-lock.json|tsconfig.editor.json)
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
    Sources/WeiBei/Stores/WorkspaceStore.swift|Sources/WeiBei/App/WeiBeiApp.swift|Sources/WeiBei/Views/ContentView.swift|Sources/WeiBei/Views/StableDocumentWorkspace.swift|Sources/WeiBeiSelfCheck/main.swift|Package.swift|Package.resolved|.github/workflows/*|script/ci_changed_scopes.sh)
      agent=true
      editor=true
      data_safety=true
      ;;
  esac

  case "$path" in
    VERSION|Package.swift|Package.resolved|package.json|package-lock.json|.github/workflows/*|script/build_and_run.sh|script/build_release_dmg.sh|script/dmg/*|script/homebrew/*|Sources/WeiBeiDev/*|Docs/releases/*|LICENSE|PRIVACY.md|THIRD_PARTY_NOTICES.md|ASSET_ATTRIBUTIONS.md|DesignSystem/assets/app-icon/*|Config/*|*.entitlements|*/Info.plist)
      release=true
      ;;
  esac

  # Node 工具脚本类型检查（npm run typecheck:tools 的触发面）。
  # 根 tsconfig.json 的 include 覆盖 DesignSystem/scripts;package.json/lockfile 变化
  # 可能改动 typescript/@types/node 版本或 typecheck:tools 本身，也必须触发。
  case "$path" in
    script/*.ts|DesignSystem/scripts/*.ts|tsconfig.json|package.json|package-lock.json)
      tools=true
      ;;
  esac
}

emit_scopes() {
  printf 'code=%s\nagent=%s\neditor=%s\ndata_safety=%s\nrelease=%s\ntools=%s\n' \
    "$code" "$agent" "$editor" "$data_safety" "$release" "$tools"
}

reset_scopes() {
  code=false
  agent=false
  editor=false
  data_safety=false
  release=false
  tools=false
}

expect_scopes() {
  local expected="$1"
  shift
  reset_scopes
  local path
  for path in "$@"; do
    classify_path "$path"
  done
  local actual
  actual="$(emit_scopes | tr '\n' ' ')"
  if [[ "$actual" != "$expected" ]]; then
    echo "scope self-check failed for $*: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

if [[ "${1:-}" == "--self-check" ]]; then
  expect_scopes \
    "code=false agent=false editor=false data_safety=false release=false tools=false " \
    "Docs/plans/example.md"
  expect_scopes \
    "code=true agent=true editor=true data_safety=true release=false tools=false " \
    "Sources/WeiBei/Stores/WorkspaceStore.swift"
  expect_scopes \
    "code=true agent=false editor=true data_safety=false release=false tools=false " \
    "Sources/WeiBei/WebEditor/src/editor.ts"
  expect_scopes \
    "code=true agent=false editor=true data_safety=false release=false tools=false " \
    "Sources/WeiBeiCore/MarkdownAttachmentStore.swift"
  expect_scopes \
    "code=true agent=false editor=false data_safety=true release=false tools=false " \
    "Tests/WeiBeiSafetyTests/CourseProjectRootSelfCheck.swift"
  expect_scopes \
    "code=true agent=false editor=false data_safety=true release=false tools=false " \
    "Sources/WeiBei/Views/SidebarView.swift" \
    "Sources/WeiBei/Views/CourseDrawerHost.swift"
  expect_scopes \
    "code=true agent=false editor=false data_safety=true release=false tools=false " \
    "Sources/WeiBeiCore/LearningModels.swift" \
    "Sources/WeiBeiCore/CourseDocumentSearchIndex.swift" \
    "Sources/WeiBeiCore/NoteSourceRelations.swift"
  expect_scopes \
    "code=true agent=true editor=true data_safety=true release=true tools=false " \
    ".github/workflows/pr-checks.yml"
  expect_scopes \
    "code=true agent=true editor=false data_safety=false release=false tools=false " \
    "Sources/WeiBeiCore/NativeAgentRuntime/NativeAgentLoop.swift"
  expect_scopes \
    "code=false agent=false editor=false data_safety=false release=true tools=false " \
    "LICENSE"
  expect_scopes \
    "code=false agent=false editor=true data_safety=false release=false tools=false " \
    "tsconfig.editor.json"
  expect_scopes \
    "code=true agent=false editor=false data_safety=false release=false tools=true " \
    "script/check-genui-math.ts" \
    "DesignSystem/scripts/build-icns.ts" \
    "tsconfig.json"
  # 依赖清单变化影响 Agent、编辑器与 TypeScript 工具链 → 全部触发。
  expect_scopes \
    "code=true agent=true editor=true data_safety=false release=true tools=true " \
    "package.json"
  expect_scopes \
    "code=true agent=true editor=true data_safety=false release=true tools=true " \
    "package-lock.json"
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
