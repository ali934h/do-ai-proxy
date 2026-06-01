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

Example model IDs available on your account:

```
deepseek-3.2
minimax-m2.5
qwen3-coder-flash
gemma-4-31B-it
llama3.3-70b-instruct
```

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
  model: "deepseek-3.2",
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
  model: "deepseek-3.2",
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
    model: "deepseek-3.2",
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
    model: "deepseek-3.2",
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
| `model` | string | Model ID — e.g. `deepseek-3.2`, `minimax-m2.5` |
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
nginx -t                              # test config
systemctl reload nginx                # reload nginx
cat /etc/nginx/conf.d/do-ai-proxy.conf  # view active config
bash /root/do-ai-proxy/update.sh      # pull latest and reload
bash /root/do-ai-proxy/uninstall.sh   # remove everything
```

## Security

- Your real IP is never forwarded — all CF-Connecting-IP, X-Forwarded-For, and related headers are stripped before the request reaches DigitalOcean
- The `DO_API_KEY` is injected by Nginx and never exposed to clients
- Requests without a valid `X-Proxy-Secret` header are rejected with `401`
- `.env` is stored with `chmod 600`
- Never expose `PROXY_SECRET` in client-side (browser) code — relay requests through a backend route
