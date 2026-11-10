# RK1828 Test Results

> **Note:** these are the original working notes. Paths refer to the original folder layout (`~/Documents/workspace/RK1828-test/…`). See the mapping table in [`../README.md`](../README.md) for where each item lives in this repo.

_Measured 2026-11-08 on a single Rockchip RK1828 M.2 card (5 GB, PCIe Gen2 x1) driven from an x86_64 Linux host
(rknn3-toolkit runtime v1.2.0). All inference ran on the RK1828; the NVIDIA GPUs in the host were idle
(checked with `nvidia-smi pmon`). Raw logs are in `bench-*.log` and `gen.log`._

## Method
- Tool: `rknn3_llm_cli --bench <n_in> <n_out>` (random-token prompt, `top_k=1`). Its built-in timer reports
  prefill (prompt processing) and generate (decode) separately. TTFT = prefill time.
- Each run loads the model fresh. Load time is not included in the tok/s figures.
- Models are RKNNAI's pre-converted builds (GRQ-quantized W4A16, 8 NPU cores), built for runtime v1.1.0 and run
  on runtime v1.2.0 without issues.
- The garbled text printed during `--bench` runs is expected (random input tokens), not a model fault.

## Models tested
| Model | HF repo / config | On-card weights | Host embed | Max ctx | KV cache |
|---|---|---:|---:|---:|---|
| Qwen3-1.7B | `RKNNAI/RK182X-LLM-Qwen3-1.7B` / `w4a16-8-32256` | 1.08 GB | 0.62 GB | 32,256 | fp16 |
| Qwen3-8B | `RKNNAI/RK1828-LLM-Qwen3-8B` / `w4a16-8-6144-kv-int4` | 4.55 GB | 1.24 GB | 6,144 | int4 |
| Qwen3.5-4B | `RKNNAI/RK1828-LLM-Qwen3.5-4B` / `w4a16-8-68608-kv-int4` | 2.65 GB | 1.27 GB | 68,608 | int4 |
| Qwen3.5-4B VLM | `RKNNAI/RK1828-VLM-Qwen3.5-4B` / `384x384-w4a16-8-68096-kv-int4` | 2.65 + 0.20 GB (vision) | 1.27 GB | 68,096 | int4 |

## Qwen3-1.7B (fp16 KV, 32k context)
| Prompt tokens | Prefill tok/s | TTFT | **Generate tok/s** | ms/token |
|---:|---:|---:|---:|---:|
| 128 | 1,506 | 0.09 s | **93.7** | 10.7 |
| 1,024 | 1,607 | 0.64 s | **94.8** | 10.5 |
| 4,096 | 1,432 | 2.9 s | **48.2** | 20.8 |
| 8,192 | 1,197 | 6.8 s | **48.6** | 20.6 |
| 16,384 | 856 | 19.1 s | **32.9** | 30.4 |
| 31,000 | 565 | 54.9 s | **25.0** | 40.1 |

Decode time rises in **~10 ms steps** with context length (10.5 → 20.7 → 30.4 → 40.1 ms). This is consistent
with the runtime processing the KV cache in fixed-size length groups (an interpretation, not confirmed
in the docs). Load + 128/128 run: about 11 s wall.

## Qwen3-8B (int4 KV, 6k context)
| Prompt tokens | Prefill tok/s | TTFT | **Generate tok/s** |
|---:|---:|---:|---:|
| 128 | 593 | 0.2 s | **49.3** |
| 1,024 | 589 | 1.7 s | **49.1** |
| 2,048 | 558 | 3.7 s | **49.9** |
| 4,096 | 502 | 8.2 s | **49.6** |
| 5,600 | 465 | 12.0 s | **49.0** |

Flat ~49 tok/s over the whole context (int4 KV is small). Model load is ~25 s (4.6 GB over Gen2 x1).

## Qwen3.5-4B (int4 KV, 68k context)
| Prompt tokens | Prefill tok/s | TTFT | **Generate tok/s** |
|---:|---:|---:|---:|
| 128 | 681 | 0.2 s | **32.3** |
| 1,024 | 759 | 1.3 s | **32.8** |
| 4,096 | 737 | 5.6 s | **33.3** |
| 16,384 | 645 | 25.4 s | **32.7** |
| 32,768 | 552 | 59.4 s | **33.2** |
| 65,536 | 429 | 152.9 s | **24.8** |

Despite smaller weights than Qwen3-8B, it decodes slower (~33 vs ~49 tok/s). Qwen3.5 mixes linear-attention
layers with regular attention and has a much larger vocabulary (lm_head), so weight size alone doesn't
predict speed across model families. Its strength: **flat speed from 128 to 32k tokens**, and still 25 tok/s
at 65k.

## Qwen3.5-4B with vision (rkllm3-server)
- Image (Rockchip `demo.jpg`, astronaut with a beer on the Moon) + "Describe this image in detail."
- **First token 1.13 s** (including image encode at 384×384), then **~33 tok/s**.
- Quality: correctly identified the astronaut, gold visor, green beer bottle, Earth, lunar surface, ladder, and
  the humorous/staged nature of the scene. One error: it called the green cooler (footrest) a "chair or
  stool". It didn't read the brand name.

## Side-by-side summary
| | Qwen3-1.7B | Qwen3-8B | Qwen3.5-4B |
|---|---:|---:|---:|
| Generate, short ctx | **95 tok/s** | 49 tok/s | 33 tok/s |
| Generate @ 16k | 33 tok/s | n/a (6k max) | 33 tok/s |
| Generate @ ~32k | 25 tok/s | n/a | 33 tok/s |
| Generate @ 65k | n/a (32k max) | n/a | 25 tok/s |
| Prefill, short ctx | ~1,500 tok/s | ~590 tok/s | ~700 tok/s |
| Max context | 32k | 6k | 68k |
| Vision | no | no | yes (VLM build) |
| Answer quality (1 prompt, subjective) | basic | good | best |

Quality sample, same prompt to both ("In three sentences: why is memory bandwidth the bottleneck for LLM token
generation?"): Qwen3.5-4B correctly explained data movement vs. arithmetic and the "memory wall". Qwen3-8B
was vaguer and partly blamed "high computational demands". This rests on one prompt only.

## Practical guidance
- **Fastest interactive chat:** Qwen3-1.7B (~95 tok/s).
- **Best short-context reasoning:** Qwen3-8B (~49 tok/s, 6k limit).
- **Long documents / RAG / code / images:** Qwen3.5-4B (~33 tok/s flat to 32k, 68k max, vision build available).

## What does NOT fit on one card
RKNNAI's larger models are pipeline-split (layer segments `llm_seg0..N`) across multiple cards:
| Model | Cards |
|---|---|
| Qwen3.5-35B-A3B | 5 |
| Qwen3-30B-A3B | 5 |
| Qwen3.8-27B | 4 |
| Qwen3.5-9B | 2 |

Pipeline parallelism adds capacity, not single-stream speed. Forlinx reports ~13 tok/s for Qwen3.8-27B on 4
cards.

## Not measured (yet)
- **Power draw.** Not measured. Forlinx states ~10 W per card under full load. Worth measuring with a meter
  on the card's external supply.
- Quality on a proper prompt set (only spot checks so far).
- Concurrent sessions (`rkllm3-server --n-session`).
