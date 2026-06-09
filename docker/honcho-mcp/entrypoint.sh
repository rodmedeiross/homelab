#!/bin/sh
set -e

# wrangler dev reads non-secret vars from .dev.vars; generate it from the
# container environment so HONCHO_API_URL can be set via compose.
: "${HONCHO_API_URL:=http://honcho-api:8000}"
echo "HONCHO_API_URL=${HONCHO_API_URL}" > /app/.dev.vars

echo "[honcho-mcp] starting wrangler dev -> :8787 (HONCHO_API_URL=${HONCHO_API_URL})"
# Run wrangler under Node (not bun). --ip 0.0.0.0 so other containers can reach it.
exec node node_modules/wrangler/bin/wrangler.js dev --ip 0.0.0.0 --port 8787
