#!/usr/bin/env python3
"""Ask the rkllm3-server (OpenAI-compatible) a question, optionally about an image. Stdlib only.

  python3 ask.py "What is in this picture?" photo.jpg
  python3 ask.py "Explain NPUs in two sentences."
  python3 ask.py --think "Solve: ..."          # enable Qwen thinking
Env: RK_URL (default http://127.0.0.1:8080), N_PREDICT (default 512)
"""
import base64, json, mimetypes, os, sys, time, urllib.request

args = sys.argv[1:]
think = "--think" in args
args = [a for a in args if a != "--think"]
if not args:
    sys.exit(__doc__)
question, image = args[0], (args[1] if len(args) > 1 else None)

content = []
if image:
    mime = mimetypes.guess_type(image)[0] or "image/jpeg"
    b64 = base64.b64encode(open(image, "rb").read()).decode()
    content.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}})
content.append({"type": "text", "text": question})

body = {
    "model": "qwen3.5-4b",
    "messages": [{"role": "user", "content": content}],
    "stream": True,
    "n_predict": int(os.environ.get("N_PREDICT", "512")),
    "chat_template_kwargs": {"enable_thinking": think},
}
url = os.environ.get("RK_URL", "http://127.0.0.1:8080") + "/v1/chat/completions"
req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})

t0 = time.time(); first = None; n = 0
with urllib.request.urlopen(req, timeout=600) as r:
    for raw in r:
        line = raw.decode("utf-8", "replace").strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        ch = json.loads(data)["choices"][0]
        txt = (ch.get("delta") or {}).get("content") or ""
        if txt:
            if first is None:
                first = time.time()
            n += 1
            print(txt, end="", flush=True)
        if ch.get("finish_reason"):
            break
t1 = time.time()
print()
if first:
    gen = t1 - first
    print(f"\n[first token {first - t0:.2f}s | {n} chunks in {gen:.1f}s ≈ {n / gen if gen > 0 else 0:.1f} tok/s]",
          file=sys.stderr)
