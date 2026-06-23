# do-ai-proxy

Nginx-based reverse proxy for the [DigitalOcean Inference API](https://docs.digitalocean.com/products/inference/).  
Hides your real IP and API key behind a VPS, with optional HTTPS via a Cloudflare origin certificate.

```
You  ──HTTP/HTTPS──▶  VPS (Nginx :4040)  ──HTTPS──▶  inference.do-ai.run
                       ↑
                   API key injected here
                   IP headers stripped here
```

## Prerequisites

- Ubuntu VPS with **root** access
- A DigitalOcean Inference API key (`doo_v1_...`)
- *(Optional)* A domain pointing at the VPS + Cloudflare origin certificate (`.pem` + `.key`) already saved on the server

## Install

One-line install (run as root):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ali934h/do-ai-proxy/main/install.sh)
```

The installer will:

- Install Nginx if not already present
- Clone this repo to `/root/do-ai-proxy`
- Prompt for `DO_API_KEY`, port (default `4040`), and whether to use a domain + SSL
- Generate a secure `PROXY_SECRET` automatically
- Write `/etc/nginx/conf.d/do-ai-proxy.conf` and reload Nginx
- Print the Base URL and secret to use in your tools

## Usage in Cline / Continue / GitHub Copilot

After install, configure your AI tool with:

| Field | Value |
|-------|-------|
| Provider | OpenAI Compatible |
| Base URL | `http://YOUR-VPS-IP:4040/v1` (or `https://your.domain/v1`) |
| API Key | *(your generated `PROXY_SECRET`)* |
| Custom Header | `X-Proxy-Secret: YOUR_PROXY_SECRET` |

---

## Available models

DigitalOcean regularly adds new models. The list of models accessible to you depends on your account subscription tier.

### Check available models

Run this script on your VPS to dynamically fetch all DO models and test which ones your account can actually use:

```bash
bash /root/do-ai-proxy/models.sh
```

The script will:

1. Fetch all models from the DO Inference API
2. Test each one through your proxy with a minimal request
3. Report `✅` (available), `❌` (subscription required), `⚠️` (not a chat model), or `⏱️` (timeout)
4. If any models timed out, ask whether to retry them
5. Print a final list of all available models

### Confirmed available models (GitHub Student / tier 1 — June 2026)

> Pricing source: [DO Inference Pricing](https://docs.digitalocean.com/products/inference/details/pricing/) — last verified June 2026.  
> Prices are per 1M tokens. `—` means not listed separately on the pricing page.  
> Sorted by coding capability (strongest first).

| Model ID | Use case | Input (per 1M) | Output (per 1M) |
|----------|----------|---------------:|----------------:|
| `deepseek-v4-pro` | Frontier, complex tasks | $1.74 | $3.48 |
| `kimi-k2.6` | Frontier | $0.95 | $4.00 |
| `qwen3.5-397b-a17b` | Powerful general | $0.55 | $3.50 |
| `nemotron-3-ultra-550b` | Frontier | $0.90 | $1.70 |
| `openai-gpt-oss-120b` | Cheap, capable | $0.10 | $0.70 |
| `qwen3-coder-flash` | Coding agent | $0.45 | $1.70 |
| `deepseek-3.2` | General, coding | $0.50 | $1.60 |
| `deepseek-r1-distill-llama-70b` | Reasoning, math | $0.99 | $0.99 |
| `kimi-k2.5` | General | $0.50 | $2.70 |
| `mimo-v2.5-pro` | Reasoning, frontier | $0.80 | $3.00 |
| `glm-5` | Coding, general | $1.00 | $3.20 |
| `glm-5.2` | Coding, general | — | — |
| `nvidia-nemotron-3-super-120b` | General | $0.30 | $0.65 |
| `llama-4-maverick` | General | $0.25 | $0.87 |
| `alibaba-qwen3-32b` | General | $0.25 | $0.55 |
| `minimax-m2.5` | General, coding | $0.30 | $1.20 |
| `deepseek-4-flash` | Fast, low cost | $0.14 | $0.28 |
| `mimo-v2.5` | Reasoning, general | $0.14 | $0.28 |
| `nemotron-3-nano-omni` | Multimodal, light | $0.50 | $0.90 |
| `llama3.3-70b-instruct` | General | $0.65 | $0.65 |
| `openai-gpt-oss-20b` | Ultra cheap | $0.05 | $0.45 |
| `gemma-4-31B-it` | Light, fast | $0.18 | $0.50 |
| `mistral-3-14B` | Light, fast | $0.20 | $0.20 |
| `nemotron-nano-12b-v2-vl` | Vision, light | $0.20 | $0.60 |
| `router:software-engineering` | Auto-routes by task | free* | free* |
| `router:general` | Auto-routes by task | free* | free* |
| `router:knowledge-base-document` | Auto-routes by task | free* | free* |
| `router:writing` | Auto-routes by task | free* | free* |

> \* Routers have no additional cost during public preview. You are billed for whichever model the router selects per request.

> **Off-peak discount (05:00–11:00 UTC):** `kimi-k2.5` → $0.35 / $1.89 &nbsp;|&nbsp; `minimax-m2.5` → $0.21 / $0.84

---

## Using the API in JavaScript / TypeScript

The proxy is fully OpenAI-compatible. You can use the official `openai` npm package or plain `fetch`.

### With the OpenAI SDK (recommended)

```bash
npm install openai
```

```ts
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://your.domain/v1",   // or http://YOUR-VPS-IP:4040/v1
  apiKey: "YOUR_PROXY_SECRET",
  defaultHeaders: {
    "X-Proxy-Secret": "YOUR_PROXY_SECRET",
  },
});

const response = await client.chat.completions.create({
  model: "deepseek-v4-pro",
  messages: [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user",   content: "Hello!" },
  ],
  temperature: 0.7,
  max_completion_tokens: 1024,
});

console.log(response.choices[0].message.content);
```

### Streaming

```ts
const stream = await client.chat.completions.create({
  model: "deepseek-v4-pro",
  messages: [{ role: "user", content: "Write a short poem." }],
  stream: true,
  max_completion_tokens: 512,
});

for await (const chunk of stream) {
  process.stdout.write(chunk.choices[0]?.delta?.content ?? "");
}
```

### With plain fetch (no dependencies)

```ts
const res = await fetch("https://your.domain/v1/chat/completions", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "X-Proxy-Secret": "YOUR_PROXY_SECRET",
  },
  body: JSON.stringify({
    model: "deepseek-v4-pro",
    messages: [{ role: "user", content: "Hello!" }],
    max_completion_tokens: 512,
  }),
});

const data = await res.json();
console.log(data.choices[0].message.content);
```

### Streaming with fetch (SSE)

```ts
const res = await fetch("https://your.domain/v1/chat/completions", {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "X-Proxy-Secret": "YOUR_PROXY_SECRET",
  },
  body: JSON.stringify({
    model: "deepseek-v4-pro",
    messages: [{ role: "user", content: "Hello!" }],
    stream: true,
    max_completion_tokens: 512,
  }),
});

const reader = res.body!.getReader();
const decoder = new TextDecoder();

while (true) {
  const { done, value } = await reader.read();
  if (done) break;

  const lines = decoder.decode(value).split("\n").filter(l => l.startsWith("data: "));
  for (const line of lines) {
    const json = line.replace("data: ", "").trim();
    if (json === "[DONE]") break;
    const chunk = JSON.parse(json);
    process.stdout.write(chunk.choices[0]?.delta?.content ?? "");
  }
}
```

### In the browser (React / Vue / plain JS)

> ⚠️ Only expose the proxy to the browser if your server is behind HTTPS. Never put the `PROXY_SECRET` in public client-side code — use a backend route to relay requests instead.

```ts
// Example: Next.js API route  →  /app/api/chat/route.ts
import { NextRequest, NextResponse } from "next/server";

export async function POST(req: NextRequest) {
  const body = await req.json();

  const res = await fetch(`${process.env.PROXY_BASE_URL}/v1/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Proxy-Secret": process.env.PROXY_SECRET!,
    },
    body: JSON.stringify(body),
  });

  const data = await res.json();
  return NextResponse.json(data);
}
```

---

## Request parameters

All parameters are passed through to DigitalOcean unchanged. The proxy only injects the `Authorization` header and strips IP-related headers.

### Required

| Parameter | Type | Description |
|-----------|------|-------------|
| `model` | string | Model ID — e.g. `deepseek-v4-pro`, `qwen3-coder-flash` |
| `messages` | array | Conversation history. Each item has `role` (`system` / `user` / `assistant`) and `content` |

### Optional — commonly used

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `temperature` | number `0–2` | `1` | Higher = more creative, lower = more focused |
| `max_completion_tokens` | integer | ~2048 | Maximum tokens in the response. Controls cost and length |
| `stream` | boolean | `false` | Stream the response token by token (SSE) |
| `stop` | string / string[] | — | Up to 4 sequences where the model stops generating |
| `seed` | integer | — | Set for reproducible outputs |
| `top_p` | number `0–1` | `1` | Alternative to temperature for controlling diversity |
| `presence_penalty` | number `-2–2` | `0` | Penalizes tokens already in the text — encourages new topics |
| `frequency_penalty` | number `-2–2` | `0` | Penalizes repeated tokens — reduces verbatim repetition |

### Optional — advanced

| Parameter | Type | Description |
|-----------|------|-------------|
| `reasoning_effort` | `low` / `medium` / `high` | Only for reasoning models (e.g. `deepseek-r1-distill-llama-70b`) |
| `tools` | array | Function definitions for tool/function calling (model must support it) |
| `tool_choice` | `none` / `auto` / `required` | Controls when the model calls a tool |
| `n` | integer | Number of completion choices to return (increases cost) |

> **Note:** Not all models support every parameter. Open-source DO-hosted models (`owned_by: digitalocean`) reliably support `temperature`, `max_completion_tokens`, `stream`, `stop`, and `seed`. Parameters like `tools` and `reasoning_effort` depend on the specific model.

---

## Daily commands

```bash
nginx -t                                  # test config
systemctl reload nginx                    # reload nginx
cat /etc/nginx/conf.d/do-ai-proxy.conf   # view active config
bash /root/do-ai-proxy/models.sh          # check available models
bash /root/do-ai-proxy/update.sh          # pull latest and reload
bash /root/do-ai-proxy/uninstall.sh       # remove everything
```

## Security

- Your real IP is never forwarded — all CF-Connecting-IP, X-Forwarded-For, and related headers are stripped before the request reaches DigitalOcean
- The `DO_API_KEY` is injected by Nginx and never exposed to clients
- Requests without a valid `X-Proxy-Secret` header are rejected with `401`
- `.env` is stored with `chmod 600`
- Never expose `PROXY_SECRET` in client-side (browser) code — relay requests through a backend route
