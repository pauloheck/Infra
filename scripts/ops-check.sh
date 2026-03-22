#!/usr/bin/env bash
###############################################################################
# ops-check.sh — Health check rápido de toda a plataforma _heck
# Uso: ./scripts/ops-check.sh
###############################################################################
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
fail() { echo -e "${RED}  ❌ $1${NC}"; }
info() { echo -e "${YELLOW}  ➜  $1${NC}"; }

echo ""
echo "════════════════════════════════════════════════"
echo "  _heck Platform — Status Check"
echo "════════════════════════════════════════════════"

# 1. Nodes
echo ""
echo "── Cluster ──────────────────────────────────────"
kubectl get nodes -o wide 2>/dev/null && ok "Nodes OK" || fail "kubectl não disponível"

# 2. Pods por namespace
echo ""
echo "── Pods ─────────────────────────────────────────"
for ns in beeai-dev beeai-prod bovipro-dev bovipro-prod iai-dev iai-prod; do
  echo "  namespace: $ns"
  if kubectl get ns "$ns" &>/dev/null; then
    kubectl get pods -n "$ns" --no-headers 2>/dev/null | while read -r line; do
      name=$(echo "$line" | awk '{print $1}')
      status=$(echo "$line" | awk '{print $3}')
      if [[ "$status" == "Running" ]]; then
        ok "$name ($status)"
      else
        fail "$name ($status)"
      fi
    done
  else
    info "namespace não existe"
  fi
done

# 3. IPs dos gateways/serviços
echo ""
echo "── LoadBalancer IPs ──────────────────────────────"
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,IP:.status.loadBalancer.ingress[0].ip" \
  --no-headers 2>/dev/null | while read -r ns name ip; do
  if [[ "$ip" == "<none>" || -z "$ip" ]]; then
    fail "$ns/$name — IP pendente"
  else
    ok "$ns/$name → http://$ip"
  fi
done

# 4. Health checks HTTP
echo ""
echo "── Health Checks ────────────────────────────────"

check_health() {
  local label=$1 ns=$2 svc=$3 path=$4
  local ip
  ip=$(kubectl get svc "$svc" -n "$ns" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [[ -n "$ip" ]]; then
    if curl -sf --max-time 5 "http://$ip$path" > /dev/null; then
      ok "$label → http://$ip$path"
    else
      fail "$label → http://$ip$path (sem resposta)"
    fi
  else
    info "$label → sem IP (namespace pode não existir)"
  fi
}

check_health "BeeAI DEV"    beeai-dev    beeai-gateway   /health/ready
check_health "BeeAI PROD"   beeai-prod   beeai-gateway   /health/ready
check_health "BoviPro DEV"  bovipro-dev  bovipro-gateway  /api/health
check_health "BoviPro PROD" bovipro-prod bovipro-gateway  /api/health
check_health "IAI DEV"      iai-dev      iai-core          /health
check_health "IAI PROD"     iai-prod     iai-core          /health

# 5. Uso de recursos
echo ""
echo "── Recursos ─────────────────────────────────────"
kubectl top nodes --no-headers 2>/dev/null || info "metrics-server não disponível"

echo ""
echo "════════════════════════════════════════════════"
