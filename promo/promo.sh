#!/usr/bin/env bash
# Asks what to retake and rebuild of the promo images and video, then runs
# promo/capture.sh and promo/build.py for just that:
#
#   promo/promo.sh
#
# Those two also run on their own, for scripts; see promo/README.md.
set -euo pipefail

PROMO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$(git -C "$PROMO_DIR" rev-parse --show-toplevel)"

if [ ! -t 0 ]; then
  echo "promo/promo.sh asks questions, so it needs a terminal." >&2
  echo "Without one: promo/capture.sh board demo, then promo/build.py board demo." >&2
  exit 1
fi

# Same order and names as capture.sh and build.py; banner is only built.
NAMES=(home board thread gallery search demo banner)
LABELS=(
  "The home screen"
  "A board in grid view"
  "A thread"
  "The fullscreen viewer on a video"
  "Search results"
  "The screen recording"
  "Only the banner, from the shots there are"
)
PICKED=(0 0 0 0 0 0 0)

ask() { # prompt, into $REPLY; end of input quits
  printf '%s' "$1"
  read -r REPLY || { echo; exit 0; }
}

taken() { # when screen [name]'s capture was last taken
  local file=promo/raw/$1.png
  [ "$1" = demo ] && file=promo/raw/demo.mp4
  if [ -e "$file" ]; then
    date -r "$file" '+taken %-d %b %Y'
  else
    echo 'not taken yet'
  fi
}

# Fills PICKED, with the first [count] names on offer.
choose_screens() {
  local count=$1 i word any
  while true; do
    printf '\nWhich ones? Type numbers to switch them on or off, then Enter.\n'
    i=0
    while [ "$i" -lt "$count" ]; do
      local mark=' ' when=''
      [ "${PICKED[$i]}" = 1 ] && mark='x'
      [ "${NAMES[$i]}" = banner ] || when="  ($(taken "${NAMES[$i]}"))"
      printf '  [%s] %d) %-8s %s%s\n' "$mark" "$((i + 1))" "${NAMES[$i]}" "${LABELS[$i]}" "$when"
      i=$((i + 1))
    done
    ask '  a) all   n) none   q) quit: '
    if [ -z "$REPLY" ]; then
      any=0
      for i in "${PICKED[@]}"; do [ "$i" = 1 ] && any=1; done
      [ "$any" = 1 ] && return 0
      echo 'Pick at least one, or q to quit.'
      continue
    fi
    for word in $REPLY; do
      case "$word" in
        a|all) i=0; while [ "$i" -lt "$count" ]; do PICKED[$i]=1; i=$((i + 1)); done ;;
        n|none) PICKED=(0 0 0 0 0 0 0) ;;
        q|quit) exit 0 ;;
        *)
          if [[ "$word" =~ ^[0-9]+$ ]] && [ "$word" -ge 1 ] && [ "$word" -le "$count" ]; then
            PICKED[$((word - 1))]=$((1 - PICKED[word - 1]))
          else
            echo "No option \"$word\"."
          fi
          ;;
      esac
    done
  done
}

picked_names() {
  local i=0
  while [ "$i" -lt "${#NAMES[@]}" ]; do
    [ "${PICKED[$i]}" = 1 ] && printf '%s ' "${NAMES[$i]}"
    i=$((i + 1))
  done
  return 0
}

retake() {
  local build_flag=() names
  names=$(picked_names)
  ask $'\nBuild the app first? No uses the one already on the simulator. [Y/n] '
  [[ "$REPLY" =~ ^[Nn] ]] && build_flag=(--no-build)
  # shellcheck disable=SC2086
  "$PROMO_DIR/capture.sh" --no-next ${build_flag[@]+"${build_flag[@]}"} $names
}

rebuild() {
  local names
  names=$(picked_names)
  if ! command -v uv >/dev/null; then
    echo "Rebuilding needs uv and ffmpeg: brew install uv ffmpeg" >&2
    exit 1
  fi
  printf '\nBuilding: %s\n' "$names"
  # shellcheck disable=SC2086
  uv run --project promo promo/build.py $names
}

show_results() {
  local changed
  changed=$(git status --short -- promo/raw screenshots docs/demo.mp4)
  if [ -z "$changed" ]; then
    printf '\nNothing changed.\n'
    return 0
  fi
  printf '\nChanged, not committed yet:\n%s\n' "$changed"

  local files=() line
  while IFS= read -r line; do
    case "$line" in
      screenshots/*|docs/demo.mp4) files+=("$line") ;;
    esac
  done < <(git ls-files --modified --others --exclude-standard -- screenshots docs/demo.mp4)
  if [ "${#files[@]}" -gt 0 ]; then
    ask $'\nOpen the new images to look at them? [Y/n] '
    [[ "$REPLY" =~ ^[Nn] ]] || open "${files[@]}"
  fi
  return 0
}

cat <<'MENU'
NekoSurf promo images

What do you want to do?
  1) Retake screens and rebuild their images
  2) Only retake screens
  3) Only rebuild images, from the captures already taken
  q) Quit
MENU

while true; do
  ask 'Choose: '
  case "$REPLY" in
    1) choose_screens 6; retake; rebuild; break ;;
    2) choose_screens 6; retake; break ;;
    3) choose_screens 7; rebuild; break ;;
    q|quit) exit 0 ;;
    *) echo 'Type 1, 2, 3 or q.' ;;
  esac
done

show_results
