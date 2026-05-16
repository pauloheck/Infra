#!/usr/bin/env bash
###############################################################################
# cluster-start.sh — Inicia AKS + PostgreSQL
# Uso: ./scripts/cluster-start.sh
# Tempo estimado: ~3-5 minutos
###############################################################################
set -euo pipefail

RG="rg-shared-dev"
AKS="aks-shared-dev"
PG="psql-heckio-dev"

echo "=== Iniciando PostgreSQL: $PG ==="
az postgres flexible-server start --resource-group "$RG" --name "$PG"
echo "PostgreSQL iniciado"

echo ""
echo "=== Iniciando AKS cluster: $AKS ==="
az aks start --resource-group "$RG" --name "$AKS"
echo "AKS iniciado"

echo ""
echo "=== Verificando pods ==="
az aks get-credentials --resource-group "$RG" --name "$AKS" --overwrite-existing --admin 2>/dev/null
kubectl get pods --all-namespaces | grep -v kube-system

echo ""
echo "════════════════════════════════════════"
echo "  Cluster ATIVO — pronto para uso"
echo "════════════════════════════════════════"
