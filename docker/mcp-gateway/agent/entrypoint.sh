#!/bin/sh
set -e

# Bootstrap credentials and project id come from env, never committed.
printf '%s' "$INFISICAL_AGENT_CLIENT_ID" > /auth/client-id
printf '%s' "$INFISICAL_AGENT_CLIENT_SECRET" > /auth/client-secret
sed "s|PROJECT_ID_PLACEHOLDER|$INFISICAL_PROJECT_ID|" /agent/secrets.tpl > /auth/secrets.tpl

exec infisical agent --config /agent/agent.yaml
