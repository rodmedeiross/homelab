# Honcho MCP worker — there is no official image, so we vendor the `mcp/`
# subdirectory of plastic-labs/honcho and run it locally via `wrangler dev`
# (workerd, fully offline — no Cloudflare account needed).
FROM oven/bun:1

WORKDIR /app

# bun is used for `bun install` (the project forbids npm), but wrangler itself
# must run under Node — under the bun runtime workerd never serves requests.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates nodejs \
    && rm -rf /var/lib/apt/lists/*

# Pin to a branch/tag/commit of plastic-labs/honcho for reproducibility.
ARG HONCHO_REF=main
RUN git clone --depth 1 --branch "${HONCHO_REF}" --filter=blob:none --sparse \
        https://github.com/plastic-labs/honcho.git /tmp/honcho \
    && git -C /tmp/honcho sparse-checkout set mcp \
    && cp -a /tmp/honcho/mcp/. /app/ \
    && rm -rf /tmp/honcho

RUN bun install

# Run non-interactively and don't phone home.
ENV WRANGLER_SEND_METRICS=false \
    CI=1

EXPOSE 8787

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
