#!/bin/bash
set -euo pipefail
lab_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$lab_dir"
mkdir -p .build dist
source_dirty=no
if [[ -n "$(git status --porcelain)" ]]; then source_dirty=yes; fi
xcodebuild -project CatalystChatLab.xcodeproj -scheme CatalystChatLab \
  -configuration Release -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath "$lab_dir/.build/DerivedData" \
  -clonedSourcePackagesDirPath "$lab_dir/.build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile \
  "LAB_SOURCE_REVISION=$(git rev-parse HEAD)" "LAB_SOURCE_DIRTY=$source_dirty" \
  build > .build/build.log 2>&1 || { grep -E 'error:|^ld:|BUILD FAILED' .build/build.log | head -30; exit 1; }
app_path="$lab_dir/.build/DerivedData/Build/Products/Release-maccatalyst/CatalystChatLab.app"
test -f "$app_path/Contents/Resources/Web/diagram.html"
test -f "$app_path/Contents/Resources/Web/mermaid.min.js"
test -f "$app_path/Contents/Resources/landscape.png"
codesign --verify --deep --strict "$app_path"
ditto "$app_path" "$lab_dir/dist/魏碑-Catalyst会话实验.app"
ditto -c -k --sequesterRsrc --keepParent "$lab_dir/dist/魏碑-Catalyst会话实验.app" "$lab_dir/dist/魏碑-Catalyst会话实验.zip"
printf '%s\n' "$lab_dir/dist/魏碑-Catalyst会话实验.app"
