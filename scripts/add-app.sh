#!/usr/bin/env bash
###############################################################################
# add-app.sh — Checklist interativo para adicionar nova aplicação à plataforma
# Uso: ./scripts/add-app.sh <nome-da-app>
#
# Este script NÃO executa as ações — ele guia o que precisa ser feito.
###############################################################################
set -euo pipefail

APP=${1:-}
if [[ -z "$APP" ]]; then
  echo "Uso: $0 <nome-da-app>  (ex: novaapp)"
  exit 1
fi

APP_UPPER=$(echo "$APP" | tr '[:lower:]' '[:upper:]')

cat <<EOF

════════════════════════════════════════════════════════════
  Checklist: Adicionando "${APP}" à plataforma _heck
════════════════════════════════════════════════════════════

1. TERRAFORM — Infra/envs/shared-dev/main.tf
   ─────────────────────────────────────────

   a) Database DEV + PROD:
      resource "azurerm_postgresql_flexible_server_database" "${APP}" { ... }
      resource "azurerm_postgresql_flexible_server_database" "${APP}_prod" {
        name = "${APP}-prod" ...
      }

   b) Key Vault DEV + PROD:
      module "kv_${APP}"      { project = "${APP}", env = var.env ... }
      module "kv_${APP}_prod" { project = "${APP}", env = "prod", name_override = "kv-${APP}-prod" ... }

   c) RBAC AKS -> KV (dev + prod):
      resource "azurerm_role_assignment" "aks_kv_${APP}"      { ... }
      resource "azurerm_role_assignment" "aks_kv_${APP}_prod" { ... }

   d) RBAC Terraform -> KV (dev + prod):
      resource "azurerm_role_assignment" "terraform_kv_${APP}"      { ... }
      resource "azurerm_role_assignment" "terraform_kv_${APP}_prod" { ... }

   e) Secrets no KV (connection strings para dev + prod):
      resource "azurerm_key_vault_secret" "${APP}_pg_connection" { ... }
      resource "azurerm_key_vault_secret" "${APP}_prod_pg_connection" { ... }

2. TERRAFORM APPLY
   ─────────────────────────────────────────
   cd Infra/envs/shared-dev
   TF_VAR_pg_admin_password="<senha>" \\
     terraform apply -var-file="shared-dev.tfvars"

3. JWT SECRET (manual após apply)
   ─────────────────────────────────────────
   az keyvault secret set --vault-name kv-${APP}-dev \\
     --name ${APP}-jwt-secret --value "\$(openssl rand -base64 48)"
   az keyvault secret set --vault-name kv-${APP}-prod \\
     --name ${APP}-jwt-secret --value "\$(openssl rand -base64 48)"

4. KUBERNETES — Infra/k8s/${APP}-dev/ e Infra/k8s/${APP}-prod/
   ─────────────────────────────────────────
   Para cada ambiente (dev e prod), criar:
     namespace.yaml, network-policy.yaml
     api/ (deployment, service, configmap, secret-provider)
     web/ (deployment, service, configmap)      [se houver frontend]
     gateway/ (deployment, service, configmap)

   Diferenças entre dev e prod:
     - namespace: ${APP}-dev vs ${APP}-prod
     - secret-provider: kv-${APP}-dev vs kv-${APP}-prod
     - configmap: ENV=dev vs ENV=prod

5. GITHUB ACTIONS — no repo da app
   ─────────────────────────────────────────
   Criar dois workflows:
     .github/workflows/deploy-dev.yml  (trigger: push em dev)
     .github/workflows/deploy-prod.yml (trigger: push em main)

   Secrets necessários (environments: dev + production):
     AZURE_CLIENT_ID
     AZURE_TENANT_ID
     AZURE_SUBSCRIPTION_ID
     ACR_NAME             = acrheckiodev
     AKS_NAME             = aks-shared-dev
     AKS_RESOURCE_GROUP   = rg-shared-dev

   gh secret set ACR_NAME           --body "acrheckiodev"   --repo pauloheck/${APP_UPPER} --env dev
   gh secret set AKS_NAME           --body "aks-shared-dev" --repo pauloheck/${APP_UPPER} --env dev
   gh secret set AKS_RESOURCE_GROUP --body "rg-shared-dev"  --repo pauloheck/${APP_UPPER} --env dev
   # Repetir para environment "production"

6. OIDC (se repo separado)
   ─────────────────────────────────────────
   az ad app create --display-name "${APP}-github-oidc"
   # Configurar federated credential para o repo pauloheck/${APP_UPPER}
   # Branches: dev (environment: dev) e main (environment: production)

════════════════════════════════════════════════════════════
EOF
