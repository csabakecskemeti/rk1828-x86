# How RK1828 inference works

A single reference for how an LLM runs on the RK1828: what runs where, what happens at boot and when a model
loads, how to call it, and its limits. Host-specific setup is in the per-host folders; this applies to all of them.
Facts are from Rockchip's docs (SDK v1.2.0, `RKLLM3_Server_User_Guide_EN.md`, the RM182X datasheet) and our own
runs. Anything **not yet tested by us** is marked _(untested)_.

## 1. The card is a separate computer

The RK1828 isn't a GPU that the host programs directly. It's a small computer on a PCIe link:

| On the card | |
|---|---|
| CPU | 3× 64-bit RISC-V cores (SRV, VRV0, VRV1) running Rockchip's firmware OS (`sudo rknn-console` opens a console into it) |
| NPU | 20 TOPS INT8, 8 cores (`--core-mask 0xff` = all 8) |
| Memory | **5 GB** 3D-stacked DRAM in the package: holds the model weights and the KV cache |
| Link to host | PCIe 2.0 x1 (~500 MB/s). The card's own maximum |
| Power | its own **12 V input** (the M.2 slot only feeds I/O). ~13.6 W avg / 29.4 W peak on a 7B model (DFRobot figures) |

The host keeps the **tokenizer** (`*.tokenizer.gguf`) and the **token embedding table** (`*.embed.bin`, read in host
RAM). Everything else (the transformer layers, the attention, the KV cache) is on the card.

## 2. The software stack

```
 client (normal user)                      rknn3_llm_cli   or   rkllm3-server (HTTP, OpenAI API)
   │  links librknn3_api.so                  └──────────────┬───────────────┘
   │                                                        │ unix socket @transfer_proxy3_native_<hash>
   ▼                                                        ▼
 rknn3_transfer_proxy (root; started by rknn3.service, one child per card, pinned to the A76 cores)
   │  /dev/pcie-rkep-<BDF>  (ioctl, mmap of BARs, DMA)
   ▼
 pcie-rkep.ko (kernel driver, DKMS)  ── PCIe Gen2 x1 ──►  RK1828 firmware (loaded at boot)
```

- **Clients run as a normal user**; only the proxy needs root (the device node is `0600 root`).
- **One model on the card at a time.** A second client fails with `MODEL_SETUP fail, ack = ACK_FAIL`. Stop the CLI
  or server before starting another. (`rkllm3-server --n-session N` serves several *sessions* of the *same* model.)

## 3. Boot sequence (Orange Pi, Rockchip arm64 package)

1. **12 V on before the host boots**, otherwise the card isn't on the PCIe bus, and a rescan won't find it.
2. The kernel loads `pcie-rkep` (`/etc/modules-load.d/pcie-rkep.conf`) → `/dev/pcie-rkep-0000:01:00.0`.
3. `rknn3.service` (enabled):
   - `ExecStartPre=rknn3_startup` → `pcie_upgrade_tool -s <BDF> uf /usr/lib/firmware/rknn3_rk1820.img -reset`.
     **The card doesn't boot its firmware by itself**; the host loads it at every power-on.
   - `ExecStart=rknn3_transfer_proxy`, `Restart=on-failure`.
4. Ready about **40-90 s after power-on**. Check: `sudo rknn-smi info` → `Online` / `OK`, or
   `rknn3_transfer_proxy devices` (no root needed) → `0000:01:00.0  0xb98e6c51  PCIE`.

On x86 the same steps are done by hand: `x86_64-linux-ubuntu/scripts/rk1828-up.sh`.

## 4. What happens when a model runs

A model is a folder with four files (RKNNAI pre-converted builds on Hugging Face):

| File | Where it goes | Size (Qwen3-1.7B / Qwen3.5-4B) |
|---|---|---|
| `*.rknn` | the compiled graph → card | 39 MB / small |
| `*.weight` | the weights → **card DRAM** | 1.08 GB / 2.65 GB |
| `*.embed.bin` | token embeddings → **host RAM** | 0.62 GB / 1.27 GB |
| `*.tokenizer.gguf` | tokenizer → host | 6 MB |

1. **Load:** the weights go over the x1 link **once**: ~5-10 s for 1.7B, ~25 s for 8B.
2. **Prefill** (reading the prompt): host tokenizes, looks up embeddings, sends them; the NPU processes the whole
   prompt. ~600-2000 tok/s depending on the model. This is **time to first token**.
3. **Generate:** one token at a time, entirely from card memory. The host only sends the next token's embedding
   and gets logits back. ~33-115 tok/s. **Limited by the card's memory bandwidth, not by the host or the link**,
   which is why an Orange Pi drives it as fast as a Threadripper.
4. The KV cache (the conversation so far) grows on the card, up to the model's built-in context limit.

## 5. Models that fit, and their speed (one card)

| Model | Generate tok/s | Prefill tok/s | Max context | Notes |
|---|---:|---:|---:|---|
| Qwen3-1.7B | ~95-118 | ~1500-2100 | 32k | fastest; basic answers; slows with long context (25 tok/s at 31k) |
| Qwen3-8B | ~49 | ~590 | **6k** | best short reasoning; 6k limit |
| Qwen3.5-4B | ~33 | ~700 | **68k** | flat speed to 32k; best answers; **KV checkpoints** supported (§6.3) |
| Qwen3.5-4B + vision | ~33 | — | 68k | image input via `rkllm3-server` |

Measured on x86 (`x86_64-linux-ubuntu/docs/TEST_RESULTS.md`); Qwen3-1.7B also on the Orange Pi (115 / 2022).
Models above ~8-9B are split across 2-5 cards (pipeline), so they won't run on one.

## 6. Two ways to call it

### 6.1 `rknn3_llm_cli` (interactive / one-shot / bench)

```bash
M=~/rk1828/models/RK182X-LLM-Qwen3-1.7B/Qwen3-1.7B-w4a16-8-32256/Qwen3-1.7B.rknn
rknn3_llm_cli --model $M --core-mask 0xff -n 1024                         # chat (Ctrl+D exits)
rknn3_llm_cli --model $M --core-mask 0xff -n 256 --prompt "..." --once    # one answer, then exit
rknn3_llm_cli --model $M --core-mask 0xff --bench 128 128                 # speed test (output text is nonsense)
```
It finds `.weight`, `.embed.bin` and `.tokenizer.gguf` next to the `.rknn` by name. It loads the model every
time, so it's fine for people, but slow for programs.

### 6.2 `rkllm3-server` (OpenAI-compatible HTTP; the one to use from code)

Keeps the model loaded. Endpoints: `GET /health`, `GET /v1/models`, `POST /v1/chat/completions` (sync and
streaming), plus slot and KV-cache endpoints. Default listen address `127.0.0.1:8080`.

Qwen3.5-4B text model on the Orange Pi _(untested on the Orange Pi; same flags as the tested x86 vision setup,
`x86_64-linux-ubuntu/scripts/serve-qwen35-vl.sh`, minus the vision model)_:

```bash
D=~/rk1828/models/RK1828-LLM-Qwen3.5-4B/Qwen3.5-4B-w4a16-8-68608-kv-int4
rkllm3-server \
  -m $D/Qwen3.5-4B.rknn --weight $D/Qwen3.5-4B.weight \
  --vocab $D/Qwen3.5-4B.tokenizer.gguf --embed $D/Qwen3.5-4B.embed.bin \
  --host 127.0.0.1 --port 8080 -c 0 --n-predict 2048 \
  --repeat-penalty 1.0 --presence-penalty 1.5 --top-k 1 --top-p 0.9 --temp 1.0
# -c 0 = use the model's own context limit (68,608)
```

```bash
curl -s http://127.0.0.1:8080/health
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "messages": [{"role":"user","content":"Say hi in five words."}],
  "chat_template_kwargs": {"enable_thinking": false}
}'
```

Useful request extras (in the JSON body, or `extra_body` with the OpenAI SDK):
- `"chat_template_kwargs": {"enable_thinking": false}`: no `<think>` block (faster answers).
  `--reasoning-format deepseek` on the server puts thinking into `reasoning_content` instead of `content`.
- `n_predict`, `temperature`, `top_k`, `top_p`: per request.

### 6.3 Features that matter for an agent _(documented, untested by us)_

- **Tool calling (OpenAI format).** Send `tools` (and optionally `tool_choice`: `auto`/`none`/`required`/a
  specific tool). The response has `message.tool_calls` and `finish_reason: "tool_calls"`. Tool calls are only
  parsed into `tool_calls` **when the request carries `tools`**; without it the model may print raw
  `<tool_call>` tags into the text. Multi-turn: send the tool result back as a `role: "tool"` message.
- **Grammar-constrained output.** `json_schema` / `response_format`, or an EBNF `grammar`, forces the output
  (including tool calls) to be valid. Rockchip recommends this for reliable tool-call formats: "without a syntax
  constraint, the structured output of a tool call depends entirely on the model's capability". **Use it with
  small models.**
- **KV-cache reuse, so the system prompt isn't re-read every turn.** A long system prompt plus tool definitions
  costs prefill time on every request (e.g. 4,000 tokens ≈ 5-6 s on Qwen3.5-4B).
  - `save_kvcache_path` / `load_kvcache_path` in the request: compute the system prompt's KV once, save it, load
    it before each new conversation.
  - Checkpoints (`checkpoint_start_pos`, `checkpoint_interval`, …): automatic snapshots during a conversation.
    **Only for Qwen3.5 / Gemma4-type models**, another reason to prefer Qwen3.5-4B.
- **Sessions:** `--n-session N` (max 16) runs several independent conversations of the same model (each needs card
  memory for its KV cache).

## 7. Limits and failure modes

| Symptom | Meaning / fix |
|---|---|
| `MODEL_SETUP fail, ack = ACK_FAIL` | another model is already on the card. Stop the other CLI/server |
| client hangs at `rknn3_init`, 0 interrupts | firmware not running. On the Orange Pi: `sudo systemctl restart rknn3.service`; check `sudo rknn-console` shows `magic=524b4550` |
| card missing from `lspci` | no 12 V at boot. Power it, then reboot the host |
| `rknn-smi` prints nothing / exits 255 | needs `sudo`; options go after `info` |
| `[ETH] config file read failed ... /tmp/rk-mdns.ini` in the proxy log | harmless (network-card discovery, `rknn-mdns` disabled) |
| proxy won't stop | `sudo kill -9 $(pgrep -x rknn3_transfer_)`. **Never** `rmmod` the driver while a proxy runs |
| bench prints "[ERROR] The system has encountered an error" | that's the model's text reply to random tokens, not an error |

Other limits: one model at a time; no hot-swap without stopping the client; 5 GB card memory caps the size
(about 8-9B with int4 KV); context limit is baked into each model build (6k / 32k / 68k).

## 8. Where things are (Orange Pi)

| Path | What |
|---|---|
| `/usr/bin/{rknn3_llm_cli, rkllm3-server, rknn-smi, rknn-console, rknn3_transfer_proxy, pcie_upgrade_tool}` | tools from the deb |
| `/usr/lib/firmware/rknn3_rk1820.img` | card firmware (M.2 2280) |
| `rknn3.service` | firmware load + proxy, every boot |
| `~/rk1828/models/` | models (`download-models.sh` pins exact builds and verifies SHA256) |
| `~/rk1828/results/` | benchmark logs |

More: [`orangepi5plus-arm64-ubuntu/BRINGUP_LOG.md`](orangepi5plus-arm64-ubuntu/BRINGUP_LOG.md) (every setup step),
[`x86_64-linux-ubuntu/docs/`](x86_64-linux-ubuntu/docs/) (x86 port, all benchmarks, dead ends), and Rockchip's
`RKLLM3_Server_User_Guide_EN.md` in `x86_64-linux-ubuntu/vendor/rknn3-toolkit-v1.2.0-x86_64/rkllm3-server/`.
