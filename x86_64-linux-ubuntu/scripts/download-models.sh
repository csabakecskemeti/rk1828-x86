#!/bin/bash
# Download the exact RKNNAI pre-converted models used in the tests (pinned commits) and verify SHA256.
# Usage: ./scripts/download-models.sh [all|qwen3-1.7b|qwen3-8b|qwen3.5-4b|qwen3.5-4b-vl]   (default: all)
#
# Default mode: huggingface_hub CLI (pip install -U huggingface_hub -> provides `hf`). Fast: many parallel
#   connections and CPU threads.
# GENTLE=1: low-load mode for small boards with a weak power supply (an Orange Pi 5 Plus reset twice during `hf`
#   downloads; see orangepi5plus-arm64-ubuntu/BRINGUP_LOG.md). Needs only curl. Downloads the files listed in the
#   recorded checksums one at a time, one connection, speed-capped, lowest CPU+IO priority, resumable (re-run after
#   an interruption and it continues), then verifies SHA256.
#     RATE=4M        speed cap per file (curl --limit-rate syntax), default 4M
#     SCREEN_OFF=1   also blank the GNOME screen (DPMS) during the download; it comes back on when the script exits
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
M=$ROOT/models
GENTLE=${GENTLE:-0}
if [ "$GENTLE" = 1 ]; then
  command -v curl >/dev/null || { echo "GENTLE=1 needs curl" >&2; exit 1; }
else
  command -v hf >/dev/null || { echo "install the HF CLI: pip install -U huggingface_hub (or use GENTLE=1)" >&2; exit 1; }
fi

if [ "${SCREEN_OFF:-0}" = 1 ]; then
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
  screen() { busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig \
               org.gnome.Mutter.DisplayConfig PowerSaveMode i "$1" 2>/dev/null || true; }
  screen 1; trap 'screen 0' EXIT          # PowerSaveMode 1 = screen off, 0 = on
fi

get_gentle() {  # repo  commit  config-dir  dst
  local repo=$1 rev=$2 cfg=$3 dst=$4 f
  local sums=$M/checksums/$(basename "$repo")/$cfg/SHA256SUMS
  [ -f "$sums" ] || { echo "no recorded checksums: $sums" >&2; return 1; }
  mkdir -p "$dst/$cfg"
  for f in $(awk '{print $2}' "$sums"); do
    echo "$(date +%T)   $f"
    mkdir -p "$(dirname "$dst/$cfg/$f")"
    nice -n 19 ionice -c3 curl -fL --retry 5 -C - --limit-rate "${RATE:-4M}" -sS \
      -o "$dst/$cfg/$f" "https://huggingface.co/$repo/resolve/$rev/$cfg/$f"
    sync
  done
  cp "$sums" "$dst/$cfg/SHA256SUMS"
}

get() {  # repo  commit  config-dir
  local repo=$1 rev=$2 cfg=$3 dst=$M/$(basename "$1")
  echo "== $repo @ $rev  ($cfg)"
  if [ "$GENTLE" = 1 ]; then
    get_gentle "$repo" "$rev" "$cfg" "$dst"
    (cd "$dst/$cfg" && sha256sum -c SHA256SUMS) && echo "matches tested build"
  else
    hf download "$repo" --revision "$rev" --include "README.md" "LICENSE" "$cfg/**" --local-dir "$dst"
    (cd "$dst/$cfg" && sha256sum -c SHA256SUMS)
    # cross-check against the checksums recorded when the tests were run
    diff -q "$dst/$cfg/SHA256SUMS" "$M/checksums/$(basename "$repo")/$cfg/SHA256SUMS" && echo "matches tested build"
  fi
}

want=${1:-all}
[[ $want == all || $want == qwen3-1.7b ]]    && get RKNNAI/RK182X-LLM-Qwen3-1.7B  42fe8b3ae6ba6c512bd2da8ecd138c44beee4781 Qwen3-1.7B-w4a16-8-32256
[[ $want == all || $want == qwen3-8b ]]      && get RKNNAI/RK1828-LLM-Qwen3-8B    fe66e2472c7d1187bde89702188daddce9e3c9ef Qwen3-8B-w4a16-8-6144-kv-int4
[[ $want == all || $want == qwen3.5-4b ]]    && get RKNNAI/RK1828-LLM-Qwen3.5-4B  114189681566fee05fd459131dd8ab889d5566b9 Qwen3.5-4B-w4a16-8-68608-kv-int4
[[ $want == all || $want == qwen3.5-4b-vl ]] && get RKNNAI/RK1828-VLM-Qwen3.5-4B  7c3cad771891c14e485f2a74f38a0dbc37cc61b1 Qwen3.5-4B-384x384-w4a16-8-68096-kv-int4
echo "done. Models in $M"
