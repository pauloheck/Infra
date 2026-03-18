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
for ns in beeai bovipro; do
  echo "  namespace: $ns"
  kubectl get pods -n "$ns" --no-headers 2>/dev/null | while read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    status=$(echo "$line" | awk '{print $3}')
    if [[ "$status" == "Running" ]]; then
      ok "$name ($status)"
    else
      fail "$name ($status)"
    fi
  done
done

# 3. IPs dos gateways
echo ""
echo "── Gateways (LoadBalancer IPs) ──────────────────"
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
BEEAI_IP=$(kubectl get svc beeai-gateway -n beeai \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
BOVIPRO_IP=$(kubectl get svc bovipro-gateway -n bovipro \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -n "$BEEAI_IP" ]]; then
  if curl -sf --max-time 5 "http://$BEEAI_IP/health/ready" > /dev/null; then
    ok "BeeAI  → http://$BEEAI_IP/health/ready"
  else
    fail "BeeAI  → http://$BEEAI_IP/health/ready (sem resposta)"
  fi
else
  info "BeeAI  → gateway sem IP ainda"
fi

if [[ -n "$BOVIPRO_IP" ]]; then
  if curl -sf --max-time 5 "http://$BOVIPRO_IP/api/health" > /dev/null; then
    ok "BoviPro → http://$BOVIPRO_IP/api/health"
  else
    fail "BoviPro → http://$BOVIPRO_IP/api/health (sem resposta)"
  fi
else
  info "BoviPro → gateway sem IP ainda"
fi

# 5. Uso de recursos
echo ""
echo "── Recursos ─────────────────────────────────────"
kubectl top nodes --no-headers 2>/dev/null || info "metrics-server não disponível"

echo ""
echo "════════════════════════════════════════════════"
