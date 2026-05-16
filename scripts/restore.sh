#!/usr/bin/env bash
###############################################################################
# restore.sh — Restaura backup após o apply
#
# Restaura na ordem:
#   1. JWT secrets → Key Vaults (mantém os mesmos tokens entre ciclos)
#   2. PostgreSQL (beeai + getchat) via pod temporário no AKS
#   3. Azure AI Search (getnet-docs) via REST API — upsert dos documentos
#
# Uso:
#   ./scripts/restore.sh                      # usa scripts/backups/latest
#   ./scripts/restore.sh 2026-05-09_14-30     # usa backup específico
#   ./scripts/restore.sh --skip-pg            # pula PostgreSQL
#   ./scripts/restore.sh --skip-search        # pula AI Search
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ROOT="$SCRIPT_DIR/backups"

# Determinar diretório de backup
BACKUP_TIMESTAMP=""
SKIP_PG=false
SKIP_SEARCH=false
for arg in "$@"; do
  [[ "$arg" == "--skip-pg"     ]] && SKIP_PG=true     && continue
  [[ "$arg" == "--skip-search" ]] && SKIP_SEARCH=true && continue
  [[ -z "$BACKUP_TIMESTAMP"   ]] && BACKUP_TIMESTAMP="$arg"
done

if [[ -n "$BACKUP_TIMESTAMP" ]]; then
  BACKUP_DIR="$BACKUP_ROOT/$BACKUP_TIMESTAMP"
else
  BACKUP_DIR=$(readlink -f "$BACKUP_ROOT/latest" 2>/dev/null || echo "")
fi

if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
  echo "ERRO: Nenhum backup encontrado em $BACKUP_ROOT"
  echo "      Execute backup.sh antes do destroy, ou informe o timestamp:"
  echo "      ./scripts/restore.sh 2026-05-09_14-30"
  exit 1
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
info() { echo -e "${YELLOW}  ➜  $1${NC}"; }

echo ""
echo "════════════════════════════════════════════════"
echo "  _heck Platform — Restore"
echo "  Fonte: $BACKUP_DIR"
echo "════════════════════════════════════════════════"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/.env" 2>/dev/null || true

# ════════════════════════════════════════════════
# 1. JWT secrets
# ════════════════════════════════════════════════
echo ""
echo "=== [1/3] JWT secrets ==="

JWT_FILE="$BACKUP_DIR/secrets/jwt-secrets.env"
if [[ ! -f "$JWT_FILE" ]]; then
  info "Arquivo de JWT secrets não encontrado — gerando novos"
  # Gerar novos secrets se não houver backup
  declare -A KV_SECRETS=(
    [kv-beeai-shareddev]="jwt-secret-key"
    [kv-beeai-prod]="jwt-secret-key"
    [kv-bovipro-dev]="bovipro-jwt-secret"
    [kv-bovipro-prod]="bovipro-jwt-secret"
    [kv-iai-shareddev]="jwt-secret-key"
    [kv-iai-prod]="jwt-secret-key"
    [kv-getchat-dev]="jwt-secret-key"
  )
  for KV in "${!KV_SECRETS[@]}"; do
    SECRET_NAME="${KV_SECRETS[$KV]}"
    echo -n "  $KV → $SECRET_NAME (novo) ... "
    az keyvault secret set \
      --vault-name "$KV" \
      --name "$SECRET_NAME" \
      --value "$(openssl rand -base64 48)" \
      --output none
    echo "ok"
  done
else
  info "Restaurando JWT secrets do backup..."
  while IFS='=' read -r KEY VALUE; do
    [[ -z "$KEY" || "$KEY" == \#* ]] && continue
    # KEY formato: kv-nome__secret-name
    KV="${KEY%%__*}"
    SECRET_NAME="${KEY##*__}"
    echo -n "  $KV → $SECRET_NAME ... "
    az keyvault secret set \
      --vault-name "$KV" \
      --name "$SECRET_NAME" \
      --value "$VALUE" \
      --output none 2>/dev/null && echo "ok" || echo "falhou (KV ainda não disponível?)"
  done < "$JWT_FILE"
fi

ok "JWT secrets configurados"

# ════════════════════════════════════════════════
# 2. PostgreSQL
# ════════════════════════════════════════════════
echo ""
echo "=== [2/3] PostgreSQL ==="

if [[ "$SKIP_PG" == "true" ]]; then
  info "PostgreSQL: pulado (--skip-pg)"
else
  PG_DIR="$BACKUP_DIR/postgres"
  if [[ ! -d "$PG_DIR" || -z "$(ls -A "$PG_DIR" 2>/dev/null)" ]]; then
    info "Nenhum dump PostgreSQL no backup — pulando"
  else
    PG_HOST="psql-heckio-dev.postgres.database.azure.com"
    PG_USER="pgadmin"
    _KV_CONN=$(az keyvault secret show --vault-name kv-getchat-dev --name pg-connection-string --query value -o tsv 2>/dev/null || echo "")
    if [[ -n "$_KV_CONN" ]]; then
      PG_PASS=$(python3 -c "import re,sys; m=re.match(r'[^:]+://[^:]+:([^@]+)@', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$_KV_CONN")
    else
      PG_PASS="${TF_VAR_pg_admin_password:-}"
    fi

    if [[ -z "$PG_PASS" ]]; then
      info "Senha PostgreSQL não encontrada (Key Vault + TF_VAR) — pulando PostgreSQL"
    else
      # Garantir que kubectl está configurado
      if ! kubectl cluster-info &>/dev/null; then
        az aks get-credentials \
          --resource-group rg-shared-dev \
          --name aks-shared-dev \
          --admin --overwrite-existing 2>/dev/null || true
      fi

      info "Aguardando PostgreSQL estar disponível..."
      for i in $(seq 1 20); do
        kubectl run pg-probe --image=postgres:16-alpine --restart=Never \
          --namespace=default --env="PGPASSWORD=$PG_PASS" \
          --command -- pg_isready -h "$PG_HOST" -U "$PG_USER" \
          &>/dev/null && break || true
        kubectl delete pod pg-probe -n default --grace-period=0 &>/dev/null || true
        sleep 10
      done

      info "Criando pod temporário para restore..."
      kubectl run pg-restore \
        --image=postgres:16-alpine \
        --restart=Never \
        --namespace=default \
        --env="PGPASSWORD=$PG_PASS" \
        --command -- sleep 600 2>/dev/null || \
      kubectl get pod pg-restore -n default &>/dev/null

      kubectl wait pod/pg-restore -n default \
        --for=condition=Ready --timeout=60s

      for DB in beeai getchat; do
        DUMP_FILE="$PG_DIR/$DB.dump"
        [[ ! -f "$DUMP_FILE" ]] && info "$DB: dump não encontrado, pulando" && continue

        echo -n "  Restore $DB ... "
        # pg_restore com --clean recria tabelas; --if-exists evita erros se tabela não existe
        kubectl exec -i pg-restore -n default -- \
          env PGSSLMODE=require \
          pg_restore \
            --host="$PG_HOST" \
            --username="$PG_USER" \
            --dbname="$DB" \
            --no-password \
            --clean \
            --if-exists \
            --no-owner \
          < "$DUMP_FILE" 2>/dev/null || true
        echo "ok"
      done

      kubectl delete pod pg-restore -n default --grace-period=0 2>/dev/null || true
      ok "PostgreSQL restaurado"
    fi
  fi
fi

# ════════════════════════════════════════════════
# 3. Azure AI Search
# ════════════════════════════════════════════════
echo ""
echo "=== [3/3] Azure AI Search ==="

if [[ "$SKIP_SEARCH" == "true" ]]; then
  info "AI Search: pulado (--skip-search)"
else
  SEARCH_DIR="$BACKUP_DIR/search"
  INDEX="getnet-docs"
  DOCS_FILE="$SEARCH_DIR/${INDEX}-docs.json"

  if [[ ! -f "$DOCS_FILE" ]]; then
    info "Nenhum backup de AI Search encontrado — rodando ingestion completa..."
    GETCHAT_DIR="$SCRIPT_DIR/../../demo_chat_getnet"
    if [[ -d "$GETCHAT_DIR" ]]; then
      cd "$GETCHAT_DIR"
      docker compose --profile ingestion run --rm ingestion python -m src.main crawl
      ok "Ingestion completa executada"
    else
      info "demo_chat_getnet não encontrado — faça a ingestion manualmente"
    fi
  else
    SEARCH_ENDPOINT="https://search-getchat-dev.search.windows.net"
    SEARCH_KEY=$(az search admin-key show \
      --service-name search-getchat-dev \
      --resource-group rg-shared-dev \
      --query primaryKey -o tsv 2>/dev/null || echo "")

    if [[ -z "$SEARCH_KEY" ]]; then
      info "AI Search não encontrado — pulando"
    else
      info "Importando documentos do backup para $INDEX ..."

      # Recriar índice com o schema do backup (se disponível)
      SCHEMA_FILE="$SEARCH_DIR/${INDEX}-schema.json"
      if [[ -f "$SCHEMA_FILE" ]]; then
        curl -sf -X DELETE \
          "${SEARCH_ENDPOINT}/indexes/${INDEX}?api-version=2024-07-01" \
          -H "api-key: $SEARCH_KEY" &>/dev/null || true

        curl -sf -X PUT \
          "${SEARCH_ENDPOINT}/indexes/${INDEX}?api-version=2024-07-01" \
          -H "api-key: $SEARCH_KEY" \
          -H "Content-Type: application/json" \
          -d @"$SCHEMA_FILE" &>/dev/null
      fi

      # Upsert documentos em batches de 100
      DOC_COUNT=$(python3 -c "import sys,json; print(len(json.load(open('$DOCS_FILE'))))" 2>/dev/null || echo "0")
      info "Importando $DOC_COUNT documentos em batches de 100..."

      python3 - <<PYEOF
import json, urllib.request, math

docs = json.load(open("$DOCS_FILE"))
endpoint = "$SEARCH_ENDPOINT"
index = "$INDEX"
key = "$SEARCH_KEY"
batch_size = 100

for i in range(0, len(docs), batch_size):
    batch = docs[i:i+batch_size]
    # Remover campos de metadados do Search que não são campos do schema
    for doc in batch:
        doc.pop("@search.score", None)
        doc.pop("@search.highlights", None)

    payload = json.dumps({"value": [dict(d, **{"@search.action": "mergeOrUpload"}) for d in batch]}).encode()
    req = urllib.request.Request(
        f"{endpoint}/indexes/{index}/docs/index?api-version=2024-07-01",
        data=payload,
        headers={"api-key": key, "Content-Type": "application/json"},
        method="POST"
    )
    resp = urllib.request.urlopen(req)
    batch_num = i // batch_size + 1
    total = math.ceil(len(docs) / batch_size)
    print(f"  Batch {batch_num}/{total}: {len(batch)} docs OK")

print(f"Total: {len(docs)} documentos importados")
PYEOF

      ok "AI Search restaurado: $DOC_COUNT documentos"
    fi
  fi
fi

# ════════════════════════════════════════════════
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Restore concluído!${NC}"
echo "  Fonte: $BACKUP_DIR"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
