#!/bin/bash
# Run rknn3_llm_cli with one of the tested models. Normal user; proxy must be up (sudo ./rk1828-up.sh).
# Usage:
#   ./run-llm.sh qwen3.5-4b                          # interactive chat (Ctrl+D quits, /help)
#   ./run-llm.sh qwen3-8b --prompt "Hi" --once -n 256
#   ./run-llm.sh qwen3-1.7b --bench 128 128          # benchmark
# Models: qwen3-1.7b | qwen3-8b | qwen3.5-4b   (vision model: use ./serve-qwen35-vl.sh)
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
CLI=$ROOT/rknn3-toolkit/rknn3-runtime/examples/rknn3_llm_cli/install/rknn3_llm_cli_x86_64/rknn3_llm_cli
case ${1:-} in
  qwen3-1.7b) MDL=$ROOT/models/RK182X-LLM-Qwen3-1.7B/Qwen3-1.7B-w4a16-8-32256/Qwen3-1.7B.rknn ;;
  qwen3-8b)   MDL=$ROOT/models/RK1828-LLM-Qwen3-8B/Qwen3-8B-w4a16-8-6144-kv-int4/Qwen3-8B.rknn ;;
  qwen3.5-4b) MDL=$ROOT/models/RK1828-LLM-Qwen3.5-4B/Qwen3.5-4B-w4a16-8-68608-kv-int4/Qwen3.5-4B.rknn ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
MODEL_KEY=$1
shift
[ -f "$MDL" ] || { echo "model missing: run ./download-models.sh $MODEL_KEY" >&2; exit 1; }
exec "$CLI" --model "$MDL" --core-mask 0xff "$@"
