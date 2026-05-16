#!/usr/bin/env bash
###############################################################################
# backup.sh — Backup completo antes do destroy
#
# Salva localmente:
#   1. JWT secrets de todos os Key Vaults
#   2. Dump PostgreSQL (beeai + getchat) via pod temporário no AKS
#   3. Índice AI Search (getnet-docs) via REST API
#
# Output: scripts/backups/YYYY-MM-DD_HH-MM/
#         scripts/backups/latest -> link para o backup mais recente
#
# Uso:
#   ./scripts/backup.sh              # backup completo
#   ./scripts/backup.sh --skip-pg   # pula PostgreSQL (mais rápido)
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ROOT="$SCRIPT_DIR/backups"
TIMESTAMP="$(date +%Y-%m-%d_%H-%M)"
BACKUP_DIR="$BACKUP_ROOT/$TIMESTAMP"
SKIP_PG=false
for arg in "$@"; do [[ "$arg" == "--skip-pg" ]] && SKIP_PG=true; done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✅ $1${NC}"; }
info() { echo -e "${YELLOW}  ➜  $1${NC}"; }

mkdir -p "$BACKUP_DIR"

echo ""
echo "════════════════════════════════════════════════"
echo "  _heck Platform — Backup"
echo "  Destino: $BACKUP_DIR"
echo "════════════════════════════════════════════════"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/.env" 2>/dev/null || true

# ════════════════════════════════════════════════
# 1. JWT secrets — todos os Key Vaults
# ════════════════════════════════════════════════
echo ""
echo "=== [1/3] JWT secrets ==="

declare -A KV_SECRETS=(
  [kv-beeai-shareddev]="jwt-secret-key"
  [kv-beeai-prod]="jwt-secret-key"
  [kv-bovipro-dev]="bovipro-jwt-secret"
  [kv-bovipro-prod]="bovipro-jwt-secret"
  [kv-iai-shareddev]="jwt-secret-key"
  [kv-iai-prod]="jwt-secret-key"
  [kv-getchat-dev]="jwt-secret-key"
)

mkdir -p "$BACKUP_DIR/secrets"
JWT_FILE="$BACKUP_DIR/secrets/jwt-secrets.env"
: > "$JWT_FILE"

for KV in "${!KV_SECRETS[@]}"; do
  SECRET_NAME="${KV_SECRETS[$KV]}"
  echo -n "  $KV → $SECRET_NAME ... "
  VALUE=$(az keyvault secret show \
    --vault-name "$KV" \
    --name "$SECRET_NAME" \
    --query value -o tsv 2>/dev/null || echo "")
  if [[ -n "$VALUE" ]]; then
    echo "${KV}__${SECRET_NAME}=${VALUE}" >> "$JWT_FILE"
    echo "ok"
  else
    echo "não encontrado (skip)"
  fi
done

ok "JWT secrets salvos em secrets/jwt-secrets.env"

# ════════════════════════════════════════════════
# 2. PostgreSQL — dump via pod temporário no AKS
# ════════════════════════════════════════════════
echo ""
echo "=== [2/3] PostgreSQL ==="

if [[ "$SKIP_PG" == "true" ]]; then
  info "PostgreSQL: pulado (--skip-pg)"
else
  mkdir -p "$BACKUP_DIR/postgres"

  PG_HOST="psql-heckio-dev.postgres.database.azure.com"
  PG_USER="pgadmin"
  # Tenta ler a senha da connection string no Key Vault (mais confiável que TF_VAR)
  _KV_CONN=$(az keyvault secret show --vault-name kv-getchat-dev --name pg-connection-string --query value -o tsv 2>/dev/null || echo "")
  if [[ -n "$_KV_CONN" ]]; then
    PG_PASS=$(python3 -c "import re,sys; m=re.match(r'[^:]+://[^:]+:([^@]+)@', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$_KV_CONN")
  else
    PG_PASS="${TF_VAR_pg_admin_password:-}"
  fi

  if [[ -z "$PG_PASS" ]]; then
    info "TF_VAR_pg_admin_password não definida — pulando PostgreSQL"
  else
    # Verificar se kubectl está configurado
    if ! kubectl cluster-info &>/dev/null; then
      info "kubectl não configurado para o cluster — configurando..."
      az aks get-credentials \
        --resource-group rg-shared-dev \
        --name aks-shared-dev \
        --admin --overwrite-existing 2>/dev/null || true
    fi

    # Criar pod temporário para pg_dump (PostgreSQL está em VNet privada)
    info "Criando pod temporário para pg_dump..."
    kubectl run pg-backup \
      --image=postgres:16-alpine \
      --restart=Never \
      --namespace=default \
      --env="PGPASSWORD=$PG_PASS" \
      --command -- sleep 600 2>/dev/null || \
    kubectl get pod pg-backup -n default &>/dev/null  # já existe

    kubectl wait pod/pg-backup -n default \
      --for=condition=Ready --timeout=60s

    for DB in beeai getchat; do
      echo -n "  Dump $DB ... "
      kubectl exec pg-backup -n default -- \
        env PGSSLMODE=require \
        pg_dump \
          --host="$PG_HOST" \
          --username="$PG_USER" \
          --dbname="$DB" \
          --no-password \
          --format=custom \
          --compress=9 \
        > "$BACKUP_DIR/postgres/$DB.dump"
      SIZE=$(du -sh "$BACKUP_DIR/postgres/$DB.dump" | cut -f1)
      echo "ok ($SIZE)"
    done

    kubectl delete pod pg-backup -n default --grace-period=0 2>/dev/null || true
    ok "PostgreSQL dumps salvos em postgres/"
  fi
fi

# ════════════════════════════════════════════════
# 3. Azure AI Search — exportar índice getnet-docs
# ════════════════════════════════════════════════
echo ""
echo "=== [3/3] Azure AI Search ==="

mkdir -p "$BACKUP_DIR/search"

SEARCH_ENDPOINT="https://search-getchat-dev.search.windows.net"
SEARCH_KEY=$(az search admin-key show \
  --service-name search-getchat-dev \
  --resource-group rg-shared-dev \
  --query primaryKey -o tsv 2>/dev/null || echo "")

if [[ -z "$SEARCH_KEY" ]]; then
  info "AI Search não encontrado — pulando"
else
  INDEX="getnet-docs"
  info "Exportando índice $INDEX ..."

  # Exportar schema do índice
  curl -sf \
    "${SEARCH_ENDPOINT}/indexes/${INDEX}?api-version=2024-07-01" \
    -H "api-key: $SEARCH_KEY" \
    > "$BACKUP_DIR/search/${INDEX}-schema.json"

  # Exportar todos os documentos (paginado, até 100K docs)
  TOP=1000
  SKIP=0
  ALL_DOCS="[]"
  while true; do
    BATCH=$(curl -sf \
      "${SEARCH_ENDPOINT}/indexes/${INDEX}/docs?api-version=2024-07-01&\$top=${TOP}&\$skip=${SKIP}&\$select=*" \
      -H "api-key: $SEARCH_KEY" || echo '{"value":[]}')
    COUNT=$(echo "$BATCH" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('value',[])))" 2>/dev/null || echo "0")
    ALL_DOCS=$(echo "$ALL_DOCS" "$BATCH" | python3 -c "
import sys, json
parts = sys.stdin.read().split('\n', 1)
acc = json.loads(parts[0])
batch = json.loads(parts[1]).get('value', [])
print(json.dumps(acc + batch))
" 2>/dev/null || echo "$ALL_DOCS")
    [[ "$COUNT" -lt "$TOP" ]] && break
    SKIP=$((SKIP + TOP))
  done

  echo "$ALL_DOCS" > "$BACKUP_DIR/search/${INDEX}-docs.json"
  DOC_COUNT=$(echo "$ALL_DOCS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
  ok "AI Search: $DOC_COUNT documentos salvos em search/${INDEX}-docs.json"
fi

# ════════════════════════════════════════════════
# Finalizar — atualizar link "latest"
# ════════════════════════════════════════════════
ln -sfn "$BACKUP_DIR" "$BACKUP_ROOT/latest"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Backup concluído!${NC}"
echo "  Diretório: $BACKUP_DIR"
echo "  Link:      $BACKUP_ROOT/latest"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
