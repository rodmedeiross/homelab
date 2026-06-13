# MCP Gateway config

Config for the `docker/mcp-gateway` container (service `mcp-gateway` in
`docker-compose.ai-client.yaml`). On the gateway host, symlink the bind-mount path to
this repo folder (same pattern as the comfyui image) so repo updates apply directly:
```
ln -s <repo>/docker/mcp-gateway/config /srv/ai/mcp-gateway/config
```
The gateway bind-mounts `/srv/ai/mcp-gateway/config:/mcp:ro`. `secrets.env` lives in
this folder (gitignored). It is rendered by the `infisical-agent` sidecar from the
vault, not created by hand. Symlink the agent folder the same way:
```
ln -s <repo>/docker/mcp-gateway/agent /srv/ai/mcp-gateway/agent
```
The agent bind-mounts `/srv/ai/mcp-gateway/config:/out` and writes `secrets.env` there.

## Files
- `catalog.yaml` — server catalog. Exposes one server, `honcho`, as a `remote`
  (streamable-http) entry pointing at the `honcho-mcp` worker (same host, `mcp_net`).
- `secrets.env` — **not in git**. Holds `HONCHO_API_KEY` (Honcho admin JWT), injected
  into the upstream `Authorization` header. Create from `secrets.env.example`.

## Topology
The gateway and the `honcho-mcp` worker run together on one host (local bridge
`mcp_net`); the worker reaches the upstream Honcho API over the LAN via its
published port. `HONCHO_API_URL` is a **Portainer stack env** referenced as
`${HONCHO_API_URL}` in the compose — not baked into the image.
```
client -> NPM / Cloudflare Tunnel -> mcp-gateway:8811/mcp
       -> (injects Honcho headers) -> honcho-mcp:8787 -> ${HONCHO_API_URL}
```

## How servers are enabled
The gateway command uses `--servers=honcho`, so `registry.yaml` is not needed.
Add more servers by listing them in `catalog.yaml` and extending `--servers`.

## Build the worker image (on the host, like comfyui)
```
docker build -t honcho-mcp:local <repo>/docker/honcho-mcp
```

## Security before exposing to the internet
The streaming gateway has no built-in client auth. Put an auth layer in front
(Cloudflare Access policy on the tunnel, or Authelia via NPM) before exposing.
Also consider replacing the `docker.sock` mount with a read-only socket proxy
(e.g. `tecnativa/docker-socket-proxy`) since the gateway is internet-facing.
