#!/usr/bin/env bash
set -euo pipefail

code=false
pi=false
editor=false
data_safety=false
release=false

classify_path() {
  local path="$1"

  case "$path" in
    Sources/*|Tests/*|Package.swift|Package.resolved|package.json|package-lock.json|script/*|.github/workflows/*|VERSION|DesignSystem/*|Config/*|Vendor/PiRuntime/manifest.json)
      code=true
      ;;
  esac

  case "$path" in
    Sources/*Pi*|Sources/WeiBeiCore/AgentResources/*|Sources/WeiBeiCore/StudyAgentRuntime.swift|Sources/WeiBeiCore/Agent*|Sources/WeiBei/Views/NotesAgentView.swift|script/prepare_pi_runtime.sh|Config/PiRuntime.entitlements|Vendor/PiRuntime/manifest.json)
      pi=true
      ;;
  esac

  case "$path" in
    Sources/WeiBei/WebEditor/*|Sources/WeiBei/Resources/Editor/*|Sources/WeiBeiWebEditorCheck/*|Sources/WeiBei/Support/AgentChatKaTeXMarkdown.swift|Sources/WeiBei/Views/*Markdown*|Sources/WeiBei/Views/NotesAgentView.swift|Sources/WeiBeiCore/Markdown*.swift|package.json|package-lock.json)
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
    VERSION|Package.swift|Package.resolved|package.json|package-lock.json|.github/workflows/*|script/build_and_run.sh|script/build_release_dmg.sh|script/dmg/*|script/homebrew/*|script/prepare_pi_runtime.sh|script/verify_release_metadata.sh|script/verify_production_hygiene.sh|Docs/releases/*|LICENSE|PRIVACY.md|THIRD_PARTY_NOTICES.md|ASSET_ATTRIBUTIONS.md|DesignSystem/assets/app-icon/*|Config/*|Vendor/PiRuntime/manifest.json|Vendor/PiRuntime/LICENSE|Vendor/PiRuntime/THIRD_PARTY_NOTICES.md|*.entitlements|*/Info.plist)
      release=true
      ;;
  esac
}

emit_scopes() {
  printf 'code=%s\npi=%s\neditor=%s\ndata_safety=%s\nrelease=%s\n' \
    "$code" "$pi" "$editor" "$data_safety" "$release"
}

reset_scopes() {
  code=false
  pi=false
  editor=false
  data_safety=false
  release=false
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
    "code=false pi=false editor=false data_safety=false release=false " \
    "Docs/plans/example.md"
  expect_scopes \
    "code=true pi=true editor=true data_safety=true release=false " \
    "Sources/WeiBei/Stores/WorkspaceStore.swift"
  expect_scopes \
    "code=true pi=false editor=true data_safety=false release=false " \
    "Sources/WeiBei/WebEditor/src/editor.js"
  expect_scopes \
    "code=true pi=false editor=true data_safety=false release=false " \
    "Sources/WeiBeiCore/MarkdownAttachmentStore.swift"
  expect_scopes \
    "code=true pi=false editor=false data_safety=true release=false " \
    "Tests/WeiBeiSafetyTests/CourseProjectRootSelfCheck.swift"
  expect_scopes \
    "code=true pi=false editor=false data_safety=true release=false " \
    "Sources/WeiBei/Views/SidebarView.swift" \
    "Sources/WeiBei/Views/CourseDrawerHost.swift"
  expect_scopes \
    "code=true pi=false editor=false data_safety=true release=false " \
    "Sources/WeiBeiCore/LearningModels.swift" \
    "Sources/WeiBeiCore/CourseDocumentSearchIndex.swift" \
    "Sources/WeiBeiCore/NoteSourceRelations.swift"
  expect_scopes \
    "code=true pi=true editor=true data_safety=true release=true " \
    ".github/workflows/pr-checks.yml"
  expect_scopes \
    "code=true pi=true editor=false data_safety=false release=true " \
    "Vendor/PiRuntime/manifest.json"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=true " \
    "LICENSE"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=true " \
    "Vendor/PiRuntime/LICENSE"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=true " \
    "Vendor/PiRuntime/THIRD_PARTY_NOTICES.md"
  expect_scopes \
    "code=false pi=false editor=false data_safety=false release=false " \
    "Vendor/PiRuntime/README.md"
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
