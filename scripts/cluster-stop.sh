#!/usr/bin/env bash
###############################################################################
# cluster-stop.sh — Para AKS + PostgreSQL para economizar custos
# Uso: ./scripts/cluster-stop.sh
# Economia: ~R$16/dia (AKS ~R$11 + PostgreSQL ~R$5)
###############################################################################
set -euo pipefail

RG="rg-shared-dev"
AKS="aks-shared-dev"
PG="psql-heckio-dev"

echo "=== Parando AKS cluster: $AKS ==="
az aks stop --resource-group "$RG" --name "$AKS" --no-wait
echo "AKS stop iniciado (async)"

echo ""
echo "=== Parando PostgreSQL: $PG ==="
az postgres flexible-server stop --resource-group "$RG" --name "$PG"
echo "PostgreSQL parado"

echo ""
echo "════════════════════════════════════════"
echo "  Cluster PARADO — economia ~R$16/dia"
echo "  Para iniciar: ./scripts/cluster-start.sh"
echo "════════════════════════════════════════"
