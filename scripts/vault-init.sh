#!/usr/bin/env bash
###############################################################################
# vault-init.sh — Initialize HashiCorp Vault, store secrets, configure ESO
#
# Prerequisites:
#   - kubectl access to the cluster
#   - Vault pod running (deployed via ArgoCD)
#   - jq installed
#   - Secrets file at ~/.openclaw/secrets/vault-secrets.json (or override
#     with VAULT_SECRETS_FILE env var)
#
# Secrets file format (vault-secrets.json):
#   {
#     "f5_host": "172.16.10.10",
#     "f5_username": "admin",
#     "f5_password": "...",
#     "anthropic_api_key": "sk-ant-...",
#     "openai_api_key": "sk-...",
#     "xai_api_key": "xai-...",
#     "github_pat": "ghp_...",
#     "slack_bot_token": "xoxb-...",
#     "slack_app_token": "xapp-...",
#     "slack_channel_ids": "C0...",
#     "slack_team_id": "T..."
#   }
#
# Usage:
#   ./scripts/vault-init.sh
###############################################################################
set -euo pipefail

VAULT_NS="vault"
VAULT_POD="vault-0"
ESO_NS="external-secrets"
SECRETS_FILE="${VAULT_SECRETS_FILE:-$HOME/.openclaw/secrets/vault-secrets.json}"

# ── Load secrets ─────────────────────────────────────────────────────────────
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "ERROR: Secrets file not found at $SECRETS_FILE"
  echo ""
  echo "Create it with:"
  echo "  mkdir -p ~/.openclaw/secrets"
  echo '  cat > ~/.openclaw/secrets/vault-secrets.json <<EOF'
  echo '  {'
  echo '    "f5_host": "172.16.10.10",'
  echo '    "f5_username": "admin",'
  echo '    "f5_password": "YOUR_F5_PASSWORD",'
  echo '    "anthropic_api_key": "sk-ant-...",'
  echo '    "openai_api_key": "sk-...",'
  echo '    "xai_api_key": "xai-...",'
  echo '    "github_pat": "ghp_...",'
  echo '    "slack_bot_token": "xoxb-...",'
  echo '    "slack_app_token": "xapp-...",'
  echo '    "slack_channel_ids": "C0...",'
  echo '    "slack_team_id": "T..."'
  echo '  }'
  echo '  EOF'
  echo ""
  echo "Or set VAULT_SECRETS_FILE to point to your secrets file."
  exit 1
fi

F5_HOST=$(jq -r '.f5_host' "$SECRETS_FILE")
F5_USERNAME=$(jq -r '.f5_username' "$SECRETS_FILE")
F5_PASSWORD=$(jq -r '.f5_password' "$SECRETS_FILE")
ANTHROPIC_API_KEY=$(jq -r '.anthropic_api_key' "$SECRETS_FILE")
OPENAI_API_KEY=$(jq -r '.openai_api_key' "$SECRETS_FILE")
XAI_API_KEY=$(jq -r '.xai_api_key' "$SECRETS_FILE")
GITHUB_PAT=$(jq -r '.github_pat' "$SECRETS_FILE")
SLACK_BOT_TOKEN=$(jq -r '.slack_bot_token // empty' "$SECRETS_FILE")
SLACK_APP_TOKEN=$(jq -r '.slack_app_token // empty' "$SECRETS_FILE")
SLACK_CHANNEL_IDS=$(jq -r '.slack_channel_ids // empty' "$SECRETS_FILE")
SLACK_TEAM_ID=$(jq -r '.slack_team_id // empty' "$SECRETS_FILE")

# Validate all secrets are present
for var in F5_HOST F5_USERNAME F5_PASSWORD ANTHROPIC_API_KEY OPENAI_API_KEY XAI_API_KEY GITHUB_PAT; do
  if [[ -z "${!var}" || "${!var}" == "null" ]]; then
    echo "ERROR: Missing '$var' in $SECRETS_FILE"
    exit 1
  fi
done

echo "============================================"
echo " HashiCorp Vault Initialization"
echo "============================================"
echo " Secrets loaded from: $SECRETS_FILE"
echo ""

# ── Wait for Vault pod ──────────────────────────────────────────────────────
echo "[1/7] Waiting for Vault pod to be ready..."
kubectl -n "$VAULT_NS" wait --for=condition=Ready pod/"$VAULT_POD" --timeout=180s 2>/dev/null || {
  echo "  Vault pod not in Ready state yet — checking if it's running but sealed..."
  kubectl -n "$VAULT_NS" wait --for=jsonpath='{.status.phase}'=Running pod/"$VAULT_POD" --timeout=180s
}

# ── Initialize Vault (1 key share, 1 threshold) ─────────────────────────────
echo "[2/7] Initializing Vault with 1 unseal key..."
INIT_OUTPUT=$(kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- vault operator init \
  -key-shares=1 \
  -key-threshold=1 \
  -format=json 2>/dev/null) || {
  echo "  Vault may already be initialized. Checking status..."
  STATUS=$(kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- vault status -format=json 2>/dev/null || true)
  if echo "$STATUS" | jq -e '.initialized == true' >/dev/null 2>&1; then
    echo "  Vault is already initialized."
    echo "  If you need the unseal key and token, check your previous init output."
    echo "  To continue with secret storage, export VAULT_TOKEN and VAULT_UNSEAL_KEY"
    echo "  then re-run this script with: SKIP_INIT=1 ./scripts/vault-init.sh"
    exit 1
  fi
  exit 1
}

UNSEAL_KEY=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')

echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  SAVE THESE CREDENTIALS — THEY CANNOT BE RECOVERED!    │"
echo "  ├─────────────────────────────────────────────────────────┤"
printf "  │  Unseal Key : %-40s│\n" "$UNSEAL_KEY"
printf "  │  Root Token : %-40s│\n" "$ROOT_TOKEN"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""

# ── Unseal Vault ─────────────────────────────────────────────────────────────
echo "[3/7] Unsealing Vault..."
kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- vault operator unseal "$UNSEAL_KEY" >/dev/null
echo "  Vault unsealed successfully."

# ── Enable KV v2 secrets engine ──────────────────────────────────────────────
echo "[4/7] Enabling KV v2 secrets engine at secret/..."
kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT_TOKEN" \
  vault secrets enable -path=secret -version=2 kv 2>/dev/null || {
  echo "  KV v2 engine already enabled at secret/"
}

# ── Write F5 BIG-IP credentials ─────────────────────────────────────────────
echo "[5/7] Writing F5 BIG-IP credentials to secret/data/f5/bigip..."
kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT_TOKEN" \
  vault kv put secret/f5/bigip \
    host="$F5_HOST" \
    username="$F5_USERNAME" \
    password="$F5_PASSWORD"
echo "  F5 BIG-IP credentials stored."

# ── Write LLM provider API keys ─────────────────────────────────────────────
echo "[6/7] Writing LLM provider API keys to secret/data/llm..."
kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT_TOKEN" \
  vault kv put secret/llm \
    anthropic-api-key="$ANTHROPIC_API_KEY" \
    openai-api-key="$OPENAI_API_KEY" \
    xai-api-key="$XAI_API_KEY"
echo "  LLM provider API keys stored."

# ── Write GitHub PAT ──────────────────────────────────────────────────────────
echo "[7/9] Writing GitHub PAT to secret/data/github..."
kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT_TOKEN" \
  vault kv put secret/github \
    personal-access-token="$GITHUB_PAT"
echo "  GitHub PAT stored."

# ── Write Slack credentials (optional) ────────────────────────────────────────
echo "[8/9] Writing Slack credentials to secret/data/slack..."
if [[ -n "$SLACK_BOT_TOKEN" && -n "$SLACK_APP_TOKEN" ]]; then
  kubectl -n "$VAULT_NS" exec "$VAULT_POD" -- \
    env VAULT_TOKEN="$ROOT_TOKEN" \
    vault kv put secret/slack \
      SLACK_BOT_TOKEN="$SLACK_BOT_TOKEN" \
      SLACK_APP_TOKEN="$SLACK_APP_TOKEN" \
      SLACK_CHANNEL_IDS="${SLACK_CHANNEL_IDS:-}" \
      SLACK_TEAM_ID="${SLACK_TEAM_ID:-}"
  echo "  Slack credentials stored."
else
  echo "  Skipped — slack_bot_token / slack_app_token not in secrets file."
fi

# ── Create Vault token secret for External Secrets Operator ──────────────────
echo "[9/9] Creating Vault token K8s secret for External Secrets Operator..."
kubectl create namespace "$ESO_NS" 2>/dev/null || true
kubectl -n "$ESO_NS" create secret generic vault-token \
  --from-literal=token="$ROOT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "  Vault token secret created in $ESO_NS namespace."

echo ""
echo "============================================"
echo " Vault initialization complete!"
echo "============================================"
echo ""
echo " Vault UI:  http://vault.rooster.maniak.com:8200"
echo ""
echo " Secrets stored:"
echo "   - secret/data/f5/bigip    (host, username, password)"
echo "   - secret/data/llm         (anthropic-api-key, openai-api-key, xai-api-key)"
echo "   - secret/data/github      (personal-access-token)"
echo "   - secret/data/slack       (SLACK_BOT_TOKEN, SLACK_APP_TOKEN, SLACK_CHANNEL_IDS, SLACK_TEAM_ID)"
echo ""
echo " External Secrets Operator will sync these to K8s secrets"
echo " in agentgateway-system and kagent namespaces."
echo ""
echo " Next steps:"
echo "   1. Run: terraform -chdir=f5vip apply  (for Vault UI VIP)"
echo "   2. Verify: kubectl get externalsecrets -A"
echo ""
