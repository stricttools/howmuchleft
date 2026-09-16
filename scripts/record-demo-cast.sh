#!/usr/bin/env bash
#
# Record `howmuchleft demo` to an asciicast file.
#
#   scripts/record-demo-cast.sh --dry-run --out demo.cast
#   scripts/record-demo-cast.sh --record --out demo.cast [--duration 15]
#
# The asciicast is the portable form of the recording: a JSON transcript of
# every byte the binary wrote, with timings. Unlike the GIFs that
# scripts/record-demo-gifs.sh produces, it carries the escape sequences
# themselves, so a converter downstream can re-colour it or re-render it as
# animated SVG without re-running anything.
#
# What is recorded is the same animation the GIFs show: `howmuchleft demo`,
# whose sawtooth waves drive every bar and whose git, profile and directory
# labels are synthetic. Three lines, redrawn in place, all truecolor.
#
# The binary is built fresh into the work directory and runs with HOME,
# XDG_CONFIG_HOME and CLAUDE_CONFIG_DIR pointing inside it, so the recording
# cannot read or write the machine's real Claude Code state. Everything except
# the output cast stays in the work directory.

set -euo pipefail

SELF_NAME="$(basename "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE=""
OUT=""
DURATION=15
# The recorded terminal. `howmuchleft demo` draws three lines that never exceed
# 48 columns, so a 54x4 terminal holds the animation with nothing around it and
# leaves the converter no empty margin to render.
COLS=54
ROWS=4
WORKDIR="$REPO_ROOT/demo-recording.local-only"

usage() {
  cat <<EOF
usage: $SELF_NAME (--dry-run | --record) --out PATH.cast [--duration N] [--cols N] [--rows N] [--workdir DIR]

  --dry-run      print what would be built and recorded, change nothing
  --record       build howmuchleft and write the asciicast
  --out PATH     where the asciicast goes (required)
  --duration N   seconds of animation (default $DURATION)
  --cols N       recorded terminal columns (default $COLS)
  --rows N       recorded terminal rows (default $ROWS)
  --workdir DIR  build and fixture directory (default $WORKDIR)
EOF
}

die() {
  echo "$SELF_NAME: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry" ;;
    --record) MODE="record" ;;
    --out)
      shift
      [ $# -gt 0 ] || die "--out needs a path"
      OUT="$1"
      ;;
    --duration)
      shift
      [ $# -gt 0 ] || die "--duration needs a number"
      DURATION="$1"
      ;;
    --cols)
      shift
      [ $# -gt 0 ] || die "--cols needs a number"
      COLS="$1"
      ;;
    --rows)
      shift
      [ $# -gt 0 ] || die "--rows needs a number"
      ROWS="$1"
      ;;
    --workdir)
      shift
      [ $# -gt 0 ] || die "--workdir needs a path"
      WORKDIR="$1"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

[ -n "$MODE" ] || {
  usage >&2
  die "choose --dry-run or --record"
}
[ -n "$OUT" ] || {
  usage >&2
  die "--out is required"
}
for n in "$DURATION" "$COLS" "$ROWS"; do
  case "$n" in
    '' | *[!0-9]*) die "expected a positive integer, got: $n" ;;
  esac
  [ "$n" -gt 0 ] || die "expected a positive integer, got: $n"
done

if [ "$MODE" = "dry" ]; then
  cat <<EOF
$SELF_NAME --record would:

  1. build howmuchleft from $REPO_ROOT into $WORKDIR
  2. record ${DURATION}s of \`howmuchleft demo $DURATION\` in a ${COLS}x${ROWS}
     terminal, with HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME and
     CLAUDE_CONFIG_DIR inside $WORKDIR/fakehome, COLORTERM=truecolor and
     HOWMUCHLEFT_DARK=1
  3. write the asciicast to $OUT

Nothing outside $WORKDIR and that file is written.
EOF
  exit 0
fi

for prog in go asciinema; do
  command -v "$prog" >/dev/null 2>&1 || die "required program not found: $prog"
done

BIN="$WORKDIR/howmuchleft"
FAKEHOME="$WORKDIR/fakehome"
mkdir -p "$FAKEHOME/.config" "$FAKEHOME/.cache" "$FAKEHOME/.claude"
mkdir -p "$(dirname "$OUT")"

echo "$SELF_NAME: building howmuchleft from $REPO_ROOT"
(cd "$REPO_ROOT" && go build -o "$BIN" .)

echo "$SELF_NAME: recording ${DURATION}s at ${COLS}x${ROWS}"
env -i \
  PATH="/usr/bin:/bin:$(dirname "$(command -v asciinema)")" \
  HOME="$FAKEHOME" \
  XDG_CONFIG_HOME="$FAKEHOME/.config" \
  XDG_CACHE_HOME="$FAKEHOME/.cache" \
  CLAUDE_CONFIG_DIR="$FAKEHOME/.claude" \
  TERM=xterm-256color \
  COLORTERM=truecolor \
  HOWMUCHLEFT_DARK=1 \
  asciinema rec --overwrite --quiet \
  --cols "$COLS" --rows "$ROWS" \
  --command "$BIN demo $DURATION" \
  "$OUT"

echo "$SELF_NAME: wrote $OUT ($(wc -c <"$OUT") bytes)"
