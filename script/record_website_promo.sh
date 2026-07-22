#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:?usage: record_website_promo.sh OUTPUT_DIR}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAPTURE_ROOT="$(/usr/bin/mktemp -d /private/tmp/weibei-promo-XXXXXX)"
CAPTURE_DIR="$CAPTURE_ROOT/Capture"
STATUS_PATH="$CAPTURE_DIR/recording-status.txt"
VIDEO_PATH="$CAPTURE_DIR/weibei-learning-flow.mp4"
POSTER_PATH="$CAPTURE_DIR/weibei-learning-flow-poster.png"
APP_BINARY="$ROOT_DIR/dist/魏碑.app/Contents/MacOS/WeiBei"
APP_PID=""

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR" "$CAPTURE_DIR"

cd "$ROOT_DIR"
./script/build_and_run.sh package

if [[ ! -x "$APP_BINARY" ]]; then
  echo "promo capture failed: packaged WeiBei binary is missing." >&2
  exit 2
fi

/usr/bin/env \
  WEIBEI_SUPPRESS_ACTIVATION=1 \
  WEIBEI_FORCE_OFFLINE_AGENT=1 \
  WEIBEI_PI_DISABLED=1 \
  "WEIBEI_WORKSPACE_DIR=$CAPTURE_ROOT" \
  WEIBEI_VERIFY_SCENARIO=website-promo-flow \
  WEIBEI_VERIFY_WINDOW_SIZE=1440x900 \
  "WEIBEI_VERIFY_RECORDING_PATH=$VIDEO_PATH" \
  "WEIBEI_VERIFY_RECORDING_POSTER_PATH=$POSTER_PATH" \
  "WEIBEI_VERIFY_RECORDING_STATUS_PATH=$STATUS_PATH" \
  WEIBEI_VERIFY_RECORDING_FPS=8 \
  WEIBEI_VERIFY_RECORDING_DURATION=15 \
  WEIBEI_VERIFY_RECORDING_START_DELAY=1 \
  "$APP_BINARY" >"$CAPTURE_ROOT/app-stdout.log" 2>"$CAPTURE_ROOT/app-stderr.log" &
APP_PID="$!"

for _ in {1..100}; do
  if [[ -s "$STATUS_PATH" ]]; then
    break
  fi
  if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "promo capture failed: WeiBei exited before recording started." >&2
    [[ -s "$CAPTURE_ROOT/app-stderr.log" ]] && /bin/cat "$CAPTURE_ROOT/app-stderr.log" >&2
    exit 3
  fi
  sleep 0.2
done

if [[ ! -s "$STATUS_PATH" ]]; then
  echo "promo capture failed: recorder did not start." >&2
  [[ -s "$CAPTURE_ROOT/app-stderr.log" ]] && /bin/cat "$CAPTURE_ROOT/app-stderr.log" >&2
  exit 4
fi

for _ in {1..150}; do
  if /usr/bin/grep -q '^completed$' "$STATUS_PATH" 2>/dev/null; then
    break
  fi
  if /usr/bin/grep -q '^failed$' "$STATUS_PATH" 2>/dev/null; then
    /bin/cat "$STATUS_PATH" >&2
    [[ -s "$CAPTURE_ROOT/app-stderr.log" ]] && /bin/cat "$CAPTURE_ROOT/app-stderr.log" >&2
    exit 5
  fi
  if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "promo capture failed: WeiBei exited before the MP4 was finalized." >&2
    [[ -s "$CAPTURE_ROOT/app-stderr.log" ]] && /bin/cat "$CAPTURE_ROOT/app-stderr.log" >&2
    exit 6
  fi
  sleep 0.2
done

if ! /usr/bin/grep -q '^completed$' "$STATUS_PATH"; then
  echo "promo capture failed: recorder did not finalize within 30 seconds." >&2
  /bin/cat "$STATUS_PATH" >&2
  [[ -s "$CAPTURE_ROOT/app-stderr.log" ]] && /bin/cat "$CAPTURE_ROOT/app-stderr.log" >&2
  exit 7
fi
if [[ ! -s "$VIDEO_PATH" || ! -s "$POSTER_PATH" ]]; then
  echo "promo capture failed: MP4 or poster is empty." >&2
  exit 8
fi

/bin/cp "$VIDEO_PATH" "$OUTPUT_DIR/weibei-learning-flow.mp4"
/bin/cp "$POSTER_PATH" "$OUTPUT_DIR/weibei-learning-flow-poster.png"
[[ -s "$CAPTURE_ROOT/verification-state.txt" ]] && /bin/cp "$CAPTURE_ROOT/verification-state.txt" "$OUTPUT_DIR/verification-state.txt"
[[ -s "$CAPTURE_ROOT/app-stderr.log" ]] && /bin/cp "$CAPTURE_ROOT/app-stderr.log" "$OUTPUT_DIR/app-stderr.log"

echo "promo_video=$OUTPUT_DIR/weibei-learning-flow.mp4"
echo "promo_poster=$OUTPUT_DIR/weibei-learning-flow-poster.png"
