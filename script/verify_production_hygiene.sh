#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/dist/魏碑.app}"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "production hygiene check failed: missing app bundle at $APP_BUNDLE" >&2
  exit 2
fi

EXECUTABLE_NAME="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$INFO_PLIST")"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -x "$APP_BINARY" ]]; then
  echo "production hygiene check failed: missing executable $APP_BINARY" >&2
  exit 3
fi

FORBIDDEN_BINARY_MARKERS=(
  "WEIBEI_VERIFY_SCENARIO"
  "WEIBEI_SUPPRESS_ACTIVATION"
  "WEIBEI_FORCE_OFFLINE_AGENT"
  "WEIBEI_SAFETY_TEST_MODE"
  "WEIBEI_PDF_WORKER_SAFETY_TEST"
  "--self-check-imported-identity"
  "--self-check-course-project-root"
  "--self-check-background-workspace-save"
  "--safety-probe"
  "verification-state.txt"
  "weibei:verify-interaction"
  "offline-learning-flow"
  "A0C_GHOST_CHAT_TOKEN"
  "DO_NOT_TRASH.txt"
  "sample-html"
  "sample-pdf"
  "sample-md"
  "Mishkin 教材样例"
  "内置示例"
  "PDF 阅读样例"
  "ForSelfCheck"
  "SelfCheckTrash"
  "capturesAgentRequestForSelfCheck"
  "usesBackgroundWorkspacePersistenceForSelfCheck"
  "pauseWorkspacePersistenceForSelfCheck"
)

EXECUTABLES=("$APP_BINARY")
while IFS= read -r helper; do
  [[ -n "$helper" ]] && EXECUTABLES+=("$helper")
done < <(/usr/bin/find "$APP_BUNDLE/Contents/Helpers" -type f -perm -111 -print 2>/dev/null || true)

for executable in "${EXECUTABLES[@]}"; do
  binary_strings="$(/usr/bin/strings "$executable")"
  for marker in "${FORBIDDEN_BINARY_MARKERS[@]}"; do
    if /usr/bin/grep -Fq -- "$marker" <<<"$binary_strings"; then
      echo "production hygiene check failed: $executable contains '$marker'" >&2
      exit 4
    fi
  done
done

FORBIDDEN_RESOURCE_MARKERS=(
  "WEIBEI_VERIFY_SCENARIO"
  "weibei:verify-interaction"
  "self-check-spec"
  "RichAnswerVerification"
  "verification-only"
)
RESOURCE_BUNDLES=("$APP_BUNDLE"/Contents/Resources/WeiBei_*.bundle)
for marker in "${FORBIDDEN_RESOURCE_MARKERS[@]}"; do
  if /usr/bin/grep -R -a -Fq -- "$marker" "${RESOURCE_BUNDLES[@]}"; then
    echo "production hygiene check failed: resources contain '$marker'" >&2
    exit 6
  fi
done

while IFS= read -r packaged_test_resource; do
  [[ -z "$packaged_test_resource" ]] && continue
  echo "production hygiene check failed: packaged test resource $packaged_test_resource" >&2
  exit 5
done < <(
  /usr/bin/find "${RESOURCE_BUNDLES[@]}" -type f \( \
    -iname '*verification*' -o \
    -name 'rich_answer_worker_self_test.py' -o \
    -name 'weibei-single-pendulum-color-contrast-original.png' \
  \) -print
)

echo "production_hygiene=clean"
