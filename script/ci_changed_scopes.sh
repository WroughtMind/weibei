#!/usr/bin/env bash
set -euo pipefail

code=false
pi=false
editor=false
data_safety=false
release=false
rich_answer=false
tools=false

classify_path() {
  local path="$1"

  case "$path" in
    Sources/*|Tests/*|Package.swift|Package.resolved|package.json|package-lock.json|script/*|.github/workflows/*|VERSION|DesignSystem/*|Config/*|Vendor/PiRuntime/manifest.json)
      code=true
      ;;
  esac

  case "$path" in
    Sources/*Pi*|Sources/WeiBeiCore/AgentResources/*|Sources/WeiBeiCore/StudyAgentRuntime.swift|Sources/WeiBeiCore/Agent*|Sources/WeiBei/Views/NotesAgentView.swift|script/check-agent-project-tools.ts|script/prepare_pi_runtime.sh|Config/PiRuntime.entitlements|Vendor/PiRuntime/manifest.json|tsconfig.agent.json|package.json|package-lock.json)
      pi=true
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
      pi=true
      editor=true
      data_safety=true
      ;;
  esac

  case "$path" in
    VERSION|Package.swift|Package.resolved|package.json|package-lock.json|.github/workflows/*|script/build_and_run.sh|script/build_release_dmg.sh|script/dmg/*|script/homebrew/*|script/prepare_pi_runtime.sh|Sources/WeiBeiDev/*|Docs/releases/*|LICENSE|PRIVACY.md|THIRD_PARTY_NOTICES.md|ASSET_ATTRIBUTIONS.md|DesignSystem/assets/app-icon/*|Config/*|Vendor/PiRuntime/manifest.json|Vendor/PiRuntime/LICENSE|Vendor/PiRuntime/THIRD_PARTY_NOTICES.md|*.entitlements|*/Info.plist)
      release=true
      ;;
  esac

  # 原型工具面：富回答运行时（源码/脚本/embed 输出产物）与 Evidence Viewer
  # 等 Prototypes 下的 TS 工具（CI 只做类型检查，不跑生成）。
  # package.json/lockfile 变化可能改变依赖解析（workspaces 合并曾因此改变产物），必须触发。
  case "$path" in
    Prototypes/*|Sources/WeiBei/Resources/rich-answer.html|Sources/WeiBei/Resources/rich-answer-runtime.css|Sources/WeiBei/Resources/rich-answer-runtime.js|package.json|package-lock.json)
      rich_answer=true
      ;;
  esac

  # Node 工具脚本类型检查（npm run typecheck:tools 的触发面）。
  # 根 tsconfig.json 的 include 覆盖 Prototypes/RichAnswerWebRuntime/scripts/**/*.ts，
  # 因此这些原型脚本同样触发 tools；package.json/lockfile 变化可能改动
  # typescript/@types/node 版本或 typecheck:tools 本身，也必须触发。
  case "$path" in
    script/*.ts|DesignSystem/scripts/*.ts|tsconfig.json|Prototypes/RichAnswerWebRuntime/scripts/*.ts|package.json|package-lock.json)
      tools=true
      ;;
  esac
}

emit_scopes() {
  printf 'code=%s\npi=%s\neditor=%s\ndata_safety=%s\nrelease=%s\nrich_answer=%s\ntools=%s\n' \
    "$code" "$pi" "$editor" "$data_safety" "$release" "$rich_answer" "$tools"
}

reset_scopes() {
  code=false
  pi=false
  editor=false
  data_safety=false
  release=false
  rich_answer=false
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
    "code=false pi=false editor=false data_safety=false release=false rich_answer=false tools=false " \
    "Docs/plans/example.md"
  expect_scopes \
    "code=true pi=true editor=true data_safety=true release=false rich_answer=false tools=false " \
    "Sources/WeiBei/Stores/WorkspaceStore.swift"
  expect_scopes \
    "code=true pi=false editor=true data_safety=false release=false rich_answer=false tools=false " \
    "Sources/WeiBei/WebEditor/src/editor.ts"
  expect_scopes \
    "code=true pi=false editor=true data_safety=false release=false rich_answer=false tools=false " \
    "Sources/WeiBeiCore/MarkdownAttachmentStore.swift"
  expect_scopes \
    "code=true pi=false editor=false data_safety=true release=false rich_answer=false tools=false " \
    "Tests/WeiBeiSafetyTests/CourseProjectRootSelfCheck.swift"
  expect_scopes \
    "code=true pi=false editor=false data_safety=true release=false rich_answer=false tools=false " \
    "Sources/WeiBei/Views/SidebarView.swift" \
    "Sources/WeiBei/Views/CourseDrawerHost.swift"
  expect_scopes \
    "code=true pi=false editor=false data_safety=true release=false rich_answer=false tools=false " \
    "Sources/WeiBeiCore/LearningModels.swift" \
    "Sources/WeiBeiCore/CourseDocumentSearchIndex.swift" \
    "Sources/WeiBeiCore/NoteSourceRelations.swift"
  expect_scopes \
    "code=true pi=true editor=true data_safety=true release=true rich_answer=false tools=false " \
    ".github/workflows/pr-checks.yml"
  expect_scopes \
    "code=true pi=true editor=false data_safety=false release=true rich_answer=false tools=false " \
    "Vendor/PiRuntime/manifest.json"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=true rich_answer=false tools=false " \
    "LICENSE"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=true rich_answer=false tools=false " \
    "Vendor/PiRuntime/LICENSE"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=true rich_answer=false tools=false " \
    "Vendor/PiRuntime/THIRD_PARTY_NOTICES.md"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=false rich_answer=false tools=false " \
    "Vendor/PiRuntime/README.md"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=false rich_answer=true tools=false " \
    "Prototypes/RichAnswerWebRuntime/src/main.tsx"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=false rich_answer=true tools=true " \
    "Prototypes/RichAnswerWebRuntime/scripts/embed-runtime.ts"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=false rich_answer=true tools=false " \
    "Prototypes/RichAnswerEvidenceViewer/generate-evidence-package.ts" \
    "Prototypes/RichAnswerEvidenceViewer/tsconfig.json"
  expect_scopes \
    "code=true pi=false editor=false data_safety=false release=false rich_answer=true tools=false " \
    "Sources/WeiBei/Resources/rich-answer-runtime.js" \
    "Sources/WeiBei/Resources/rich-answer.html" \
    "Sources/WeiBei/Resources/rich-answer-runtime.css"
  expect_scopes \
    "code=false pi=true editor=false data_safety=false release=false rich_answer=false tools=false " \
    "tsconfig.agent.json"
  expect_scopes \
    "code=false pi=false editor=true data_safety=false release=false rich_answer=false tools=false " \
    "tsconfig.editor.json"
  expect_scopes \
    "code=true pi=false editor=false data_safety=false release=false rich_answer=false tools=true " \
    "script/check-genui-math.ts" \
    "DesignSystem/scripts/build-icns.ts" \
    "tsconfig.json"
  # 依赖清单变化影响 Pi 类型（pi-ai/pi-coding-agent）、编辑器与富回答产物解析，
  # 以及 typescript/@types/node 版本与 typecheck:tools 本身 → 全部触发。
  expect_scopes \
    "code=true pi=true editor=true data_safety=false release=true rich_answer=true tools=true " \
    "package.json"
  expect_scopes \
    "code=true pi=true editor=true data_safety=false release=true rich_answer=true tools=true " \
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
