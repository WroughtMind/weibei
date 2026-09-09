#!/bin/bash
set -euo pipefail
lab_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$lab_dir"
mkdir -p .build dist
xcodegen generate
source_dirty=no
if [[ -n "$(git status --porcelain)" ]]; then source_dirty=yes; fi
signing_identity="${LAB_SIGNING_IDENTITY:-Apple Development}"
if [[ "${CI:-}" == "true" ]]; then signing_identity=-; fi
xcodebuild -project CatalystChatLab.xcodeproj -scheme CatalystChatLab \
  -configuration Release -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath "$lab_dir/.build/DerivedData" \
  -clonedSourcePackagesDirPath "$lab_dir/.build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  "LAB_SOURCE_REVISION=$(git rev-parse HEAD)" "LAB_SOURCE_DIRTY=$source_dirty" \
  "CODE_SIGN_IDENTITY=$signing_identity" "$@" \
  build > .build/build.log 2>&1 || { awk '/error:|^ld:|BUILD FAILED/ { if (++n <= 30) print }' .build/build.log; exit 1; }
app_path="$lab_dir/.build/DerivedData/Build/Products/Release-maccatalyst/魏碑候选.app"
test -f "$app_path/Contents/Resources/Web/diagram.html"
test -f "$app_path/Contents/Resources/Web/mermaid.min.js"
test -f "$app_path/Contents/Resources/landscape.png"
test -f "$app_path/Contents/Resources/Editor/index.html"
test -f "$app_path/Contents/Resources/genui.html"
test -f "$app_path/Contents/Resources/AgentResources/system.md"
test -x "$app_path/Contents/Helpers/WeiBeiPDFTextWorker"
test -d "$app_path/Contents/PlugIns/WeiBeiWindowBridge.bundle"
codesign --verify --deep --strict "$app_path"
ditto "$app_path" "$lab_dir/dist/魏碑-Catalyst独立候选.app"
ditto -c -k --sequesterRsrc --keepParent "$lab_dir/dist/魏碑-Catalyst独立候选.app" "$lab_dir/dist/魏碑-Catalyst独立候选.zip"
printf '%s\n' "$lab_dir/dist/魏碑-Catalyst独立候选.app"
