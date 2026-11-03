#!/usr/bin/env bash
# Takes NekoSurf's promo screenshots and screen recording in the iOS
# Simulator, for promo/build.py. Run on a Mac with Xcode and Flutter, from
# anywhere in the repository:
#
#   promo/capture.sh                 # all shots and the recording
#   promo/capture.sh board demo      # only these
#   promo/capture.sh --no-build      # use the app already installed
#   DEVICE="iPhone 17 Pro" promo/capture.sh
#
# It boots a simulator in dark mode with a clean status bar (9:41, full
# signal and battery), installs the app, and then, shot by shot, says what
# to put on screen and waits for Enter. The captures go to promo/raw/.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
OUT=promo/raw
BUNDLE_ID=com.wrngwrld.Chanyan

# name|what to put on screen
SHOTS=(
  "home|The home screen: a few favorite boards and the Feed card."
  "board|A board in grid view, with good-looking thumbnails."
  "thread|A thread with images, scrolled to where replies are nested under a post."
  "gallery|The fullscreen viewer on a video, playing, with its progress bar showing."
  "search|Search, with results for a word that matches a few threads."
)
RECORDING="demo|10-20 seconds: from the home screen, open a board, scroll a little, open a thread, tap an image, swipe to a video and let it play for 2-3 seconds, then save it."

build=1
wanted=()
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) wanted+=("$arg") ;;
  esac
done

wants() {
  [ ${#wanted[@]} -eq 0 ] && return 0
  local w
  for w in "${wanted[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

command -v xcrun >/dev/null || { echo "Needs Xcode (xcrun)." >&2; exit 1; }

# The booted iPhone, else $DEVICE, else the newest iPhone Pro (not Max).
UDID=$(xcrun simctl list devices available --json | DEVICE="${DEVICE:-}" python3 -c '
import json, os, re, sys
devices = [d | {"runtime": r} for r, ds in json.load(sys.stdin)["devices"].items() for d in ds]
iphones = [d for d in devices if d["name"].startswith("iPhone")]
def version(d):
    return [int(n) for n in re.findall(r"\d+", d["runtime"].split("iOS")[-1])]
want = os.environ["DEVICE"]
booted = [d for d in iphones if d["state"] == "Booted"]
named = [d for d in iphones if d["name"] == want]
pros = [d for d in iphones if re.fullmatch(r"iPhone \d+ Pro", d["name"])]
pick = booted or named or sorted(pros, key=lambda d: (version(d), d["name"]))[-1:]
print(pick[0]["udid"] if pick else "")
')
if [ -z "$UDID" ]; then
  echo "No iPhone simulator found${DEVICE:+ named \"$DEVICE\"}. Add one in Xcode (Window > Devices and Simulators)." >&2
  exit 1
fi

echo "Booting the simulator..."
xcrun simctl boot "$UDID" 2>/dev/null || true
# Simulator.app is inside Xcode. By its path, as macOS doesn't always know
# it by name ("Unable to find application named 'Simulator'").
simulator_app="$(xcode-select -p)/Applications/Simulator.app"
if [ -d "$simulator_app" ]; then
  open "$simulator_app" --args -CurrentDeviceUDID "$UDID"
elif ! open -a Simulator --args -CurrentDeviceUDID "$UDID" 2>/dev/null; then
  echo "Couldn't open the Simulator app. Open it yourself (in Xcode: Xcode > Open Developer Tool > Simulator), then press Enter." >&2
  read -r
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override \
  --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState charged --batteryLevel 100
trap 'xcrun simctl status_bar "$UDID" clear 2>/dev/null || true' EXIT

if [ $build -eq 1 ]; then
  echo "Building the app..."
  flutter build ios --simulator --debug
  xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
fi
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

mkdir -p "$OUT"
cat <<'EOF'

Everything in these captures ends up public, on the README and the website:
pick boards and threads with nothing you wouldn't want there (no NSFW boards,
no slurs), and look at every thumbnail before you press Enter.
EOF

for shot in "${SHOTS[@]}"; do
  name=${shot%%|*}
  wants "$name" || continue
  while true; do
    printf '\n[%s] %s\nPress Enter to take it. ' "$name" "${shot#*|}"
    read -r
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null
    printf 'Saved %s. Keep it? [Y/n] ' "$OUT/$name.png"
    read -r keep
    [[ "$keep" =~ ^[Nn] ]] || break
  done
done

name=${RECORDING%%|*}
if wants "$name"; then
  while true; do
    printf '\n[%s] %s\nPress Enter to start recording. ' "$name" "${RECORDING#*|}"
    read -r
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$name.mp4" &
    pid=$!
    printf 'Recording. Press Enter to stop. '
    read -r
    kill -INT "$pid"
    wait "$pid" || true
    printf 'Saved %s. Keep it? [Y/n] ' "$OUT/$name.mp4"
    read -r keep
    [[ "$keep" =~ ^[Nn] ]] || break
  done
fi

cat <<EOF

Done. To make the promo images and video from them, commit $OUT/ and push,
then ask Claude to build them, or run (with Python's Pillow and ffmpeg):

  python3 promo/build.py
EOF
