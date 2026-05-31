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
| Base URL | `http://YOUR-VPS-IP:4040/v1` (or `https://your.domain:4040/v1`) |
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
