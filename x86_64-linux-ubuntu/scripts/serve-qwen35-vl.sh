#!/bin/bash
# Start rkllm3-server (OpenAI-compatible API) with Qwen3.5-4B + vision on the RK1828.
# Prereq: card firmware + proxy up (sudo ./scripts/rk1828-up.sh). Run as normal user.
# Settings follow Rockchip's official Qwen3.5-4B example (RKLLM3_Server_User_Guide_EN.md).
# Listens on 127.0.0.1:8080 only (local machine). Use HOST=0.0.0.0 to expose on the LAN.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
V=$ROOT/vendor/rknn3-toolkit-v1.2.0-x86_64
D=$ROOT/models/RK1828-VLM-Qwen3.5-4B/Qwen3.5-4B-384x384-w4a16-8-68096-kv-int4
export LD_LIBRARY_PATH=$V/rknn3-api/lib:$V/rkllm3-server/lib:$LD_LIBRARY_PATH

exec "$V/rkllm3-server/bin/rkllm3-server" \
  -m "$D/Qwen3.5-4B-llm.rknn" --weight "$D/Qwen3.5-4B-llm.weight" \
  --model2 "$D/Qwen3.5-4B-vision.rknn" --weight2 "$D/Qwen3.5-4B-vision.weight" \
  --vocab "$D/Qwen3.5-4B.tokenizer.gguf" --embed "$D/Qwen3.5-4B.embed.bin" \
  --host "${HOST:-127.0.0.1}" --port "${PORT:-8080}" \
  -c "${CTX:-0}" --n-predict 2048 \
  --repeat-penalty 1.0 --presence-penalty 1.5 --frequency-penalty 0 \
  --top-k 1 --top-p 0.9 --temp 1.0 \
  --img-start "<|vision_start|>" --img-end "<|vision_end|>" --img-content "<|image_pad|>" \
  --img-width 384 --img-height 384
