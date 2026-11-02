# deployxa-node

A minimal personal Xray node (VLESS + WebSocket) packaged for
[Deployxa](https://deployxa.com). The image contains **no credentials** —
everything secret is injected at runtime through environment variables.

## Runtime configuration

Set these env vars in the Deployxa panel before deploying:

| Variable    | Required | Meaning                                                        |
| ----------- | -------- | -------------------------------------------------------------- |
| `NODE_UUID` | yes*     | VLESS client UUID                                              |
| `NODE_PATH` | yes*     | WebSocket path, e.g. `/dx-xxxxxxxx`                            |

\* If a variable is left unset, the entrypoint generates a random value
and prints it to the container log once. Set both explicitly so the
values stay stable across restarts/redeploys.

## Networking

- The container listens on **internal port 3000** (the only inbound).
  nginx fronts that port: `GET /` returns `200 ok` (the platform
  health check requires a 2xx/3xx on the root path), the secret
  WebSocket path is proxied to Xray on loopback port **3001**, and
  every other path returns 404.
- Deployxa terminates HTTPS at `https://<project>.deployxa.online`
  and forwards WebSocket traffic to port 3000.

## Client setup

Point any VLESS client (Shadowrocket, v2rayN, etc.) at:

- Address: `<project>.deployxa.online`
- Port: **443**
- Transport: WebSocket over TLS (`wss`)
- UUID: the value of `NODE_UUID`
- Path: the value of `NODE_PATH`

## Build

The Dockerfile downloads the pinned official Xray-core release
(`v25.8.3`, linux-64) at image build time; no binaries are committed
to this repo.
