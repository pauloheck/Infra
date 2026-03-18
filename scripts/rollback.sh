#!/usr/bin/env bash
###############################################################################
# rollback.sh — Rollback de deploy de uma aplicação
# Uso: ./scripts/rollback.sh <app> [revision]
#   app      : beeai-api | beeai-ai | beeai-web | bovipro-api | bovipro-web
#   revision : número da revisão (opcional, padrão = revisão anterior)
#
# Exemplos:
#   ./scripts/rollback.sh beeai-api
#   ./scripts/rollback.sh bovipro-api 3
###############################################################################
set -euo pipefail

APP=${1:-}
REVISION=${2:-}

if [[ -z "$APP" ]]; then
  echo "Uso: $0 <app> [revision]"
  echo "Apps disponíveis: beeai-api, beeai-ai, beeai-web, bovipro-api, bovipro-web"
  exit 1
fi

# Determinar namespace pela app
case "$APP" in
  beeai-*)   NS="beeai" ;;
  bovipro-*) NS="bovipro" ;;
  *)
    echo "App desconhecida: $APP"
    exit 1
    ;;
esac

echo "── Histórico de revisões: $APP (namespace: $NS) ──"
kubectl rollout history "deployment/$APP" --namespace "$NS"

echo ""
if [[ -n "$REVISION" ]]; then
  echo "── Revertendo para revisão $REVISION ──"
  kubectl rollout undo "deployment/$APP" --namespace "$NS" --to-revision="$REVISION"
else
  echo "── Revertendo para revisão anterior ──"
  kubectl rollout undo "deployment/$APP" --namespace "$NS"
fi

echo ""
echo "── Aguardando rollout ──"
kubectl rollout status "deployment/$APP" --namespace "$NS" --timeout=5m

echo ""
echo "✅ Rollback de $APP concluído."
