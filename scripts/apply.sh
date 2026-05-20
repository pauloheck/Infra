#!/usr/bin/env bash
###############################################################################
# apply.sh — Cria toda a infra shared-dev do zero e configura K8s
#
# Pré-requisitos:
#   • az login (ou AZURE_CLIENT_ID/SECRET/TENANT_ID no ambiente)
#   • kubectl disponível
#   • scripts/.env com TF_VAR_* (ver scripts/.env.example)
#
# Uso:
#   ./scripts/apply.sh                  # tudo
#   ./scripts/apply.sh --skip-k8s       # só Terraform
#   ./scripts/apply.sh --skip-jwt       # sem JWT secrets
#   ./scripts/apply.sh --skip-deploy    # sem build/push/deploy das imagens
#   ./scripts/apply.sh --skip-k8s --skip-jwt
#
# Após este script:
#   • O chat está disponível na URL pública Azure (getchat-dev.eastus2.cloudapp.azure.com)
#   • Para rebuild das imagens: rode novamente sem --skip-deploy
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../envs/shared-dev"
ROOT="$SCRIPT_DIR/.."
GETCHAT_DIR="$ROOT/../demo_chat_getnet"
K8S_DIR="$GETCHAT_DIR/k8s/getchat-dev"

SKIP_K8S=false
SKIP_JWT=false
SKIP_DEPLOY=false
for arg in "$@"; do
  [[ "$arg" == "--skip-k8s"     ]] && SKIP_K8S=true
  [[ "$arg" == "--skip-jwt"     ]] && SKIP_JWT=true
  [[ "$arg" == "--skip-deploy"  ]] && SKIP_DEPLOY=true
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
info() { echo -e "${YELLOW}  ➜  $1${NC}"; }

echo ""
echo "════════════════════════════════════════════════"
echo "  _heck Platform — Apply completo"
echo "════════════════════════════════════════════════"

# ---- Variáveis sensíveis ----
# shellcheck disable=SC1091
source "$SCRIPT_DIR/.env" 2>/dev/null || true
: "${TF_VAR_pg_admin_password:?Defina TF_VAR_pg_admin_password (ou scripts/.env)}"
: "${TF_VAR_iai_device_token:?Defina TF_VAR_iai_device_token (ou scripts/.env)}"
: "${TF_VAR_getchat_anthropic_api_key:?Defina TF_VAR_getchat_anthropic_api_key (ou scripts/.env)}"

export TF_VAR_pg_admin_password TF_VAR_iai_device_token TF_VAR_getchat_anthropic_api_key

# ════════════════════════════════════════════════
# 1. Terraform apply
# ════════════════════════════════════════════════
echo ""
echo "=== [1/5] Terraform apply ==="
cd "$TF_DIR"
terraform init -reconfigure -input=false
terraform apply -var-file="shared-dev.tfvars" -auto-approve
ok "Terraform apply concluído"

# ════════════════════════════════════════════════
# 2. Credenciais AKS
# ════════════════════════════════════════════════
echo ""
echo "=== [2/5] Configurando kubectl ==="
az aks get-credentials \
  --resource-group rg-shared-dev \
  --name aks-shared-dev \
  --admin --overwrite-existing
ok "Credenciais AKS configuradas"

# ════════════════════════════════════════════════
# 3. JWT secrets
# ════════════════════════════════════════════════
if [[ "$SKIP_JWT" == "false" ]]; then
  echo ""
  echo "=== [3/5] JWT secrets ==="

  set_jwt() {
    local kv="$1" secret="$2"
    echo -n "  $kv → $secret ... "
    az keyvault secret set \
      --vault-name "$kv" \
      --name "$secret" \
      --value "$(openssl rand -base64 48)" \
      --output none
    echo "ok"
  }

  set_jwt kv-beeai-shareddev  jwt-secret-key
  set_jwt kv-beeai-prod       jwt-secret-key
  set_jwt kv-bovipro-dev      bovipro-jwt-secret
  set_jwt kv-bovipro-prod     bovipro-jwt-secret
  set_jwt kv-iai-shareddev    jwt-secret-key
  set_jwt kv-iai-prod         jwt-secret-key
  set_jwt kv-getchat-dev      jwt-secret-key

  ok "JWT secrets criados"
else
  info "[3/5] JWT secrets: pulado (--skip-jwt)"
fi

# ════════════════════════════════════════════════
# 4. K8s manifests GetChat
# ════════════════════════════════════════════════
if [[ "$SKIP_K8S" == "false" ]]; then
  echo ""
  echo "=== [4/5] GetChat — K8s manifests ==="

  if [[ ! -d "$K8S_DIR" ]]; then
    echo "ERRO: Diretório $K8S_DIR não encontrado"
    exit 1
  fi

  kubectl apply -f "$K8S_DIR/namespace.yaml"

  # Patch userAssignedIdentityID with current kubelet identity (changes after destroy+apply)
  KUBELET_CLIENT_ID=$(az aks show \
    --resource-group rg-shared-dev \
    --name aks-shared-dev \
    --query "identityProfile.kubeletidentity.clientId" -o tsv 2>/dev/null || echo "")
  if [[ -n "$KUBELET_CLIENT_ID" ]]; then
    sed "s/userAssignedIdentityID: \"[^\"]*\"/userAssignedIdentityID: \"$KUBELET_CLIENT_ID\"/" \
      "$K8S_DIR/secret-provider.yaml" | kubectl apply -f -
    ok "SecretProviderClass: userAssignedIdentityID = $KUBELET_CLIENT_ID"
  else
    kubectl apply -f "$K8S_DIR/secret-provider.yaml"
    echo "AVISO: userAssignedIdentityID não encontrado — usando valor hardcoded"
  fi
  kubectl apply -f "$K8S_DIR/gateway/configmap.yaml"
  ok "GetChat: namespace, secrets e gateway config aplicados"

  # ---------- BeeAI / BoviPro / IAI ----------
  info "BeeAI / BoviPro / IAI: rode os pipelines deploy-dev de cada repo."
else
  info "[4/5] K8s: pulado (--skip-k8s)"
fi

# ════════════════════════════════════════════════
# 5. Build, push e deploy GetChat + URL pública
# ════════════════════════════════════════════════
if [[ "$SKIP_DEPLOY" == "false" && "$SKIP_K8S" == "false" ]]; then
  echo ""
  echo "=== [5/5] GetChat — Build, push e deploy ==="

  ACR="acrheckiodev.azurecr.io"

  # Login ACR
  az acr login --name acrheckiodev

  # Build e push das imagens
  info "Build e push das imagens para $ACR ..."
  docker build -t "$ACR/getchat-api:latest" "$GETCHAT_DIR/apps/api"
  docker push "$ACR/getchat-api:latest"

  docker build -t "$ACR/getchat-ai:latest" "$GETCHAT_DIR/apps/ai"
  docker push "$ACR/getchat-ai:latest"

  docker build -t "$ACR/getchat-web:latest" \
    --build-arg NEXT_PUBLIC_API_URL="https://getchat-dev.eastus2.cloudapp.azure.com" \
    "$GETCHAT_DIR/apps/web"
  docker push "$ACR/getchat-web:latest"

  docker build -t "$ACR/getchat-ingestion:latest" "$GETCHAT_DIR/apps/ingestion"
  docker push "$ACR/getchat-ingestion:latest"

  ok "Imagens pushadas para ACR"

  # Deploy deployments
  kubectl apply -f "$K8S_DIR/api/deployment.yaml"
  kubectl apply -f "$K8S_DIR/ai/deployment.yaml"
  kubectl apply -f "$K8S_DIR/web/deployment.yaml"
  kubectl apply -f "$K8S_DIR/gateway/deployment.yaml"
  kubectl apply -f "$K8S_DIR/ingestion/deployment.yaml"
  kubectl apply -f "$K8S_DIR/ingestion/cronjob.yaml"

  # Aguardar gateway (mais rápido, não depende de KV)
  info "Aguardando gateway..."
  kubectl rollout status deployment/getchat-gateway -n getchat-dev --timeout=3m

  # Aguardar LoadBalancer IP
  info "Aguardando IP do LoadBalancer..."
  GATEWAY_IP=""
  for i in $(seq 1 30); do
    GATEWAY_IP=$(kubectl get svc getchat-gateway -n getchat-dev \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [[ -n "$GATEWAY_IP" ]] && break
    echo "    Tentativa $i/30 — aguardando 10s..."
    sleep 10
  done

  if [[ -z "$GATEWAY_IP" ]]; then
    echo "AVISO: IP do LoadBalancer não obtido após 5 min. Configure o DNS label manualmente."
  else
    # Atribuir DNS label getchat-dev ao Public IP
    NODE_RG="MC_rg-shared-dev_aks-shared-dev_eastus2"
    PIP_NAME=$(az network public-ip list --resource-group "$NODE_RG" \
      --query "[?ipAddress=='$GATEWAY_IP'].name" -o tsv 2>/dev/null || echo "")

    if [[ -n "$PIP_NAME" ]]; then
      az network public-ip update \
        --resource-group "$NODE_RG" \
        --name "$PIP_NAME" \
        --dns-name "getchat-dev" \
        --output none 2>/dev/null || true
      ok "DNS label atribuído: getchat-dev.eastus2.cloudapp.azure.com"
    fi
  fi

  # Aguardar API e AI (dependem do KV — podem demorar enquanto RBAC propaga)
  info "Aguardando API e AI service (pode levar até 3 min enquanto RBAC propaga)..."
  kubectl rollout status deployment/getchat-api -n getchat-dev --timeout=5m || true
  kubectl rollout status deployment/getchat-ai  -n getchat-dev --timeout=5m || true
  kubectl rollout status deployment/getchat-web -n getchat-dev --timeout=5m || true

  ok "Deploy GetChat concluído"
else
  info "[5/5] Deploy: pulado (--skip-deploy ou --skip-k8s)"
fi

# ════════════════════════════════════════════════
# 6. Restore de dados (se houver backup)
# ════════════════════════════════════════════════
echo ""
echo "=== [6/6] Restore de dados ==="
BACKUP_LATEST="$SCRIPT_DIR/backups/latest"
if [[ -d "$BACKUP_LATEST" || -L "$BACKUP_LATEST" ]]; then
  info "Backup encontrado em $BACKUP_LATEST — iniciando restore..."
  bash "$SCRIPT_DIR/restore.sh"
  ok "Restore concluído"
else
  info "Nenhum backup encontrado — pulando restore"
  info "Para restaurar manualmente: ./scripts/restore.sh 2026-MM-DD_HH-MM"
fi

# ════════════════════════════════════════════════
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Infra pronta!${NC}"
echo ""
echo -e "${YELLOW}  GetChat:${NC}"
echo "       Chat  → https://getchat-dev.eastus2.cloudapp.azure.com"
echo "       Admin → https://getchat-dev.eastus2.cloudapp.azure.com/admin"
echo "       API   → https://getchat-dev.eastus2.cloudapp.azure.com/api/docs"
echo ""
echo -e "${YELLOW}  Outros apps (BeeAI / BoviPro / IAI):${NC}"
echo "       gh workflow run deploy-dev.yml --repo pauloheck/BeeAI"
echo "       gh workflow run deploy-dev.yml --repo pauloheck/BOVIPRO"
echo "       gh workflow run deploy-dev.yml --repo pauloheck/IAI"
echo ""
echo -e "${YELLOW}  Verificar saúde:${NC}"
echo "       ./scripts/ops-check.sh"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
