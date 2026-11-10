#!/bin/bash
# Download the exact RKNNAI pre-converted models used in the tests (pinned commits) and verify SHA256.
# Usage: ./download-models.sh [all|qwen3-1.7b|qwen3-8b|qwen3.5-4b|qwen3.5-4b-vl]   (default: all)
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
M=$ROOT/models
HF=$ROOT/.venv/bin/hf
command -v "$HF" >/dev/null || HF=hf
command -v "$HF" >/dev/null || { echo "install the HF CLI: pip install -U huggingface_hub" >&2; exit 1; }

get() {  # repo  commit  config-dir
  local repo=$1 rev=$2 cfg=$3 dst=$M/$(basename "$1")
  echo "== $repo @ $rev  ($cfg)"
  "$HF" download "$repo" --revision "$rev" --include "README.md" "LICENSE" "$cfg/**" --local-dir "$dst"
  (cd "$dst/$cfg" && sha256sum -c SHA256SUMS)
  # cross-check against the checksums recorded when the tests were run
  diff -q "$dst/$cfg/SHA256SUMS" "$M/checksums/$(basename "$repo")/$cfg/SHA256SUMS" && echo "matches tested build"
}

want=${1:-all}
[[ $want == all || $want == qwen3-1.7b ]]    && get RKNNAI/RK182X-LLM-Qwen3-1.7B  42fe8b3ae6ba6c512bd2da8ecd138c44beee4781 Qwen3-1.7B-w4a16-8-32256
[[ $want == all || $want == qwen3-8b ]]      && get RKNNAI/RK1828-LLM-Qwen3-8B    fe66e2472c7d1187bde89702188daddce9e3c9ef Qwen3-8B-w4a16-8-6144-kv-int4
[[ $want == all || $want == qwen3.5-4b ]]    && get RKNNAI/RK1828-LLM-Qwen3.5-4B  114189681566fee05fd459131dd8ab889d5566b9 Qwen3.5-4B-w4a16-8-68608-kv-int4
[[ $want == all || $want == qwen3.5-4b-vl ]] && get RKNNAI/RK1828-VLM-Qwen3.5-4B  7c3cad771891c14e485f2a74f38a0dbc37cc61b1 Qwen3.5-4B-384x384-w4a16-8-68096-kv-int4
echo "done. Models in $M"
