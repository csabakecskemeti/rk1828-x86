# Models

Weights are not stored in git. Download the exact tested builds with `../scripts/download-models.sh`.

| Key | Hugging Face repo @ commit | Config | Size |
|---|---|---|---:|
| `qwen3-1.7b` | `RKNNAI/RK182X-LLM-Qwen3-1.7B` @ `42fe8b3a…` (tag v1.1.0) | `Qwen3-1.7B-w4a16-8-32256` | 1.7 GB |
| `qwen3-8b` | `RKNNAI/RK1828-LLM-Qwen3-8B` @ `fe66e247…` | `Qwen3-8B-w4a16-8-6144-kv-int4` | 5.8 GB |
| `qwen3.5-4b` | `RKNNAI/RK1828-LLM-Qwen3.5-4B` @ `11418968…` | `Qwen3.5-4B-w4a16-8-68608-kv-int4` | 3.9 GB |
| `qwen3.5-4b-vl` | `RKNNAI/RK1828-VLM-Qwen3.5-4B` @ `7c3cad77…` (tag v1.1.0) | `Qwen3.5-4B-384x384-w4a16-8-68096-kv-int4` | 4.1 GB |

`checksums/` holds each config's `SHA256SUMS` and `config.json` as tested; the download script checks against them.
More pre-converted RK1828 models: <https://huggingface.co/RKNNAI>. Single-card limit is ~4.5 GB of on-card weights.
Bigger models (27B, 30B-A3B, 35B-A3B, Qwen3.5-9B) are split across 2–5 cards.
