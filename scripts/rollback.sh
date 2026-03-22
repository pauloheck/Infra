#!/usr/bin/env bash
###############################################################################
# rollback.sh — Rollback de deploy de uma aplicação
# Uso: ./scripts/rollback.sh <namespace> <deployment> [revision]
#   namespace  : beeai-dev | beeai-prod | bovipro-dev | bovipro-prod | iai-dev | iai-prod
#   deployment : beeai-api | beeai-ai | beeai-web | bovipro-api | bovipro-web | iai-core
#   revision   : número da revisão (opcional, padrão = revisão anterior)
#
# Exemplos:
#   ./scripts/rollback.sh beeai-dev beeai-api
#   ./scripts/rollback.sh bovipro-prod bovipro-api 3
#   ./scripts/rollback.sh iai-dev iai-core
###############################################################################
set -euo pipefail

NS=${1:-}
APP=${2:-}
REVISION=${3:-}

if [[ -z "$NS" || -z "$APP" ]]; then
  echo "Uso: $0 <namespace> <deployment> [revision]"
  echo "Namespaces: beeai-dev, beeai-prod, bovipro-dev, bovipro-prod, iai-dev, iai-prod"
  echo "Deployments: beeai-api, beeai-ai, beeai-web, bovipro-api, bovipro-web, iai-core"
  exit 1
fi

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
echo "Rollback de $APP ($NS) concluído."
