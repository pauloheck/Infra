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
  echo "Uso: $0 <nome-da-app>  (ex: iai, novaapp)"
  exit 1
fi

APP_UPPER=$(echo "$APP" | tr '[:lower:]' '[:upper:]')

cat <<EOF

════════════════════════════════════════════════════════════
  Checklist: Adicionando "${APP}" à plataforma _heck
════════════════════════════════════════════════════════════

1. TERRAFORM — Infra/envs/shared-dev/main.tf
   ─────────────────────────────────────────
   a) Database PostgreSQL:
      resource "azurerm_postgresql_flexible_server_database" "${APP}" {
        name      = "${APP}"
        server_id = module.postgres.server_id
        charset   = "UTF8"
        collation = "en_US.utf8"
      }

   b) Key Vault:
      module "kv_${APP}" {
        source              = "../../../modules/keyvault"
        project             = "${APP}"
        env                 = var.env
        location            = var.location
        resource_group_name = azurerm_resource_group.main.name
        tags                = var.tags
        tenant_id           = data.azurerm_client_config.current.tenant_id
        enable_diagnostics  = false
        depends_on          = [module.aks]
      }

   c) RBAC AKS → KV:
      resource "azurerm_role_assignment" "aks_kv_${APP}" {
        scope                            = module.kv_${APP}.key_vault_id
        role_definition_name             = "Key Vault Secrets Officer"
        principal_id                     = module.aks.aks_identity_principal_id
        skip_service_principal_aad_check = true
        depends_on                       = [module.kv_${APP}, module.aks]
      }

   d) Connection string no KV:
      resource "azurerm_key_vault_secret" "${APP}_pg_connection" {
        name         = "${APP}-pg-connection"
        value        = "postgresql://pgadmin:\${var.pg_admin_password}@\${module.postgres.server_fqdn}:5432/${APP}?sslmode=require"
        key_vault_id = module.kv_${APP}.key_vault_id
        depends_on   = [module.kv_${APP}, module.postgres, azurerm_role_assignment.terraform_kv_${APP}]
      }

2. TERRAFORM APPLY
   ─────────────────────────────────────────
   cd Infra/envs/shared-dev
   MSYS_NO_PATHCONV=1 TF_VAR_pg_admin_password="<senha>" \\
     terraform apply -var-file="shared-dev.tfvars"

3. JWT SECRET (manual após apply)
   ─────────────────────────────────────────
   az keyvault secret set \\
     --vault-name kv-${APP}-dev \\
     --name ${APP}-jwt-secret \\
     --value "\$(openssl rand -base64 48)"

4. KUBERNETES — Infra/k8s/${APP}/
   ─────────────────────────────────────────
   Criar: namespace.yaml, network-policy.yaml
         api/ (deployment, service, configmap, secret-provider)
         web/ (deployment, service, configmap)      [se houver frontend]
         gateway/ (deployment, service, configmap)

5. GITHUB ACTIONS — no repo da app: .github/workflows/deploy-dev.yml
   ─────────────────────────────────────────
   Secrets necessários (environment: dev):
     AZURE_CLIENT_ID      = <client-id-oidc-${APP}>
     AZURE_TENANT_ID      = 7377a982-cbdf-40d4-af3d-281d65c00164
     AZURE_SUBSCRIPTION_ID = 797403f4-3d34-4417-99c3-154e6129693f
     ACR_NAME             = acrheckiodev
     AKS_NAME             = aks-shared-dev
     AKS_RESOURCE_GROUP   = rg-shared-dev

   gh secret set ACR_NAME            --body "acrheckiodev"   --repo pauloheck/${APP_UPPER} --env dev
   gh secret set AKS_NAME            --body "aks-shared-dev" --repo pauloheck/${APP_UPPER} --env dev
   gh secret set AKS_RESOURCE_GROUP  --body "rg-shared-dev"  --repo pauloheck/${APP_UPPER} --env dev

6. OIDC (se repo separado)
   ─────────────────────────────────────────
   az ad app create --display-name "${APP}-github-oidc"
   # Configurar federated credential para o repo pauloheck/${APP_UPPER}

════════════════════════════════════════════════════════════
EOF
