#!/usr/bin/env bash
###############################################################################
# destroy.sh — Destrói toda a infra shared-dev + purga Key Vaults
#
# O que é destruído:   rg-shared-dev (AKS, PostgreSQL, KVs, ACR, OpenAI, AI Search...)
# O que NÃO é destruído: rg-beeai-platform (storage do tfstate) — intencional.
#
# ATENÇÃO — imagens ACR são perdidas. Após o próximo apply.sh, rode os
#           pipelines CI/CD de cada app para reconstruir as imagens.
#
# Uso: ./scripts/destroy.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../envs/shared-dev"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║          ⚠️  DESTRUIÇÃO TOTAL DA INFRA shared-dev         ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}  Recursos que serão destruídos:${NC}"
echo "    • AKS cluster (aks-shared-dev)   → pods e volumes perdidos"
echo "    • PostgreSQL (psql-heckio-dev)   → todos os dados perdidos"
echo "    • ACR (acrheckiodev)             → todas as imagens perdidas"
echo "    • Key Vaults (todos)             → secrets perdidos"
echo "    • Azure AI Search                → índices perdidos"
echo "    • Azure OpenAI (todos)           → deploys perdidos"
echo ""
echo -e "${YELLOW}  O que NÃO será destruído:${NC}"
echo "    • rg-beeai-platform / tfstate storage (estado do Terraform)"
echo ""

read -rp "  Digite 'destruir' para confirmar: " CONFIRM
[[ "$CONFIRM" == "destruir" ]] || { echo "Abortado."; exit 1; }

# ════════════════════════════════════════════════
# 0. Backup antes de destruir
# ════════════════════════════════════════════════
echo ""
echo "=== [0/3] Backup completo antes do destroy ==="
bash "$SCRIPT_DIR/backup.sh"
echo ""

# ---- Variáveis sensíveis ----
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.env" 2>/dev/null || true
: "${TF_VAR_pg_admin_password:?Defina TF_VAR_pg_admin_password (ou scripts/.env)}"
: "${TF_VAR_iai_device_token:?Defina TF_VAR_iai_device_token (ou scripts/.env)}"
: "${TF_VAR_getchat_anthropic_api_key:?Defina TF_VAR_getchat_anthropic_api_key (ou scripts/.env)}"

export TF_VAR_pg_admin_password TF_VAR_iai_device_token TF_VAR_getchat_anthropic_api_key

# ---- Terraform destroy ----
echo ""
echo "=== [1/3] Terraform destroy ==="
cd "$TF_DIR"
terraform init -reconfigure -input=false
terraform destroy -var-file="shared-dev.tfvars" -auto-approve
echo ""
echo "  Terraform destroy concluído."

# ---- Purgar Key Vaults ----
# Soft delete mantém KVs por 7 dias; purga permite recriar com o mesmo nome.
echo ""
echo "=== [2/3] Purgando Key Vaults (soft delete) ==="
KVS=(
  kv-beeai-shareddev kv-beeai-prod
  kv-bovipro-dev     kv-bovipro-prod
  kv-iai-shareddev   kv-iai-prod
  kv-getchat-dev
)
for KV in "${KVS[@]}"; do
  echo -n "  $KV ... "
  if az keyvault purge --name "$KV" --no-wait 2>/dev/null; then
    echo "purgado"
  else
    echo "não encontrado (ok)"
  fi
done

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Infra destruída com sucesso.${NC}"
echo ""
echo -e "${YELLOW}  Backup salvo em: $SCRIPT_DIR/backups/latest${NC}"
echo -e "${YELLOW}  Para recriar:    ./scripts/apply.sh${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
