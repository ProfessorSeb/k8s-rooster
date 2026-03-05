#!/usr/bin/env bash
set -euo pipefail

# Wrapper for Terraform in this directory that:
# - Loads BIG-IP creds from a canonical local secrets file
# - Uses the host-local state path we standardize on
# - Avoids leaking secrets into shell history / logs

CMD="${1:-}"
shift || true

if [[ -z "$CMD" ]]; then
  echo "Usage: ./tf.sh <init|plan|apply|destroy|state|output|refresh> [args...]" >&2
  echo "" >&2
  echo "Env overrides:" >&2
  echo "  K8S_ROOSTER_F5VIP_STATE=/path/to/terraform.tfstate" >&2
  echo "  K8S_ROOSTER_F5VIP_SECRETS=~/.openclaw/secrets/k8s-rooster.json" >&2
  echo "  TERRAFORM_BIN=terraform" >&2
  exit 2
fi

TERRAFORM_BIN="${TERRAFORM_BIN:-$HOME/.local/bin/terraform}"
if [[ ! -x "$TERRAFORM_BIN" ]]; then
  TERRAFORM_BIN="terraform"
fi

STATE="${K8S_ROOSTER_F5VIP_STATE:-$HOME/.terraform-state/k8s-rooster/f5vip/terraform.tfstate}"
SECRETS_FILE="${K8S_ROOSTER_F5VIP_SECRETS:-$HOME/.openclaw/secrets/k8s-rooster.json}"

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required binary: $1" >&2
    exit 1
  }
}

load_bigip_creds() {
  if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "Missing secrets file: $SECRETS_FILE" >&2
    echo "Create it (chmod 600) with:" >&2
    echo '{ "bigip": { "address": "https://172.16.10.10", "username": "admin", "password": "..." } }' >&2
    exit 1
  fi

  require_bin jq

  local addr user pass
  addr="$(jq -r '.bigip.address // empty' "$SECRETS_FILE")"
  user="$(jq -r '.bigip.username // empty' "$SECRETS_FILE")"
  pass="$(jq -r '.bigip.password // empty' "$SECRETS_FILE")"

  if [[ -z "$addr" || -z "$user" || -z "$pass" ]]; then
    echo "Secrets file is missing required fields (need .bigip.address/.bigip.username/.bigip.password): $SECRETS_FILE" >&2
    exit 1
  fi

  export TF_VAR_bigip_address="$addr"
  export TF_VAR_bigip_username="$user"
  export TF_VAR_bigip_password="$pass"
}

# Always init first (cheap + ensures provider plugins are present)
# Use -input=false so it fails fast in automation.
case "$CMD" in
  init)
    load_bigip_creds
    exec "$TERRAFORM_BIN" init -input=false "$@"
    ;;
  plan|apply|destroy|refresh)
    load_bigip_creds
    "$TERRAFORM_BIN" init -input=false >/dev/null
    exec "$TERRAFORM_BIN" "$CMD" -state="$STATE" "$@"
    ;;
  state|output)
    # These do not require BIG-IP creds.
    "$TERRAFORM_BIN" init -input=false >/dev/null
    exec "$TERRAFORM_BIN" "$CMD" -state="$STATE" "$@"
    ;;
  *)
    echo "Unknown command: $CMD" >&2
    exit 2
    ;;
esac
