# Infra — Plataforma _heck

> **Fonte única de verdade para toda a infraestrutura compartilhada.**
> As aplicações (BeeAI, BoviPro, IAI, ...) fazem **apenas deploy** — não gerenciam infraestrutura.

---

## Princípio

```
┌─────────────────────────────────────────────┐
│           C:/_heck/Infra/                   │
│   Terraform · K8s Manifests · CI/CD Infra   │
│   Scripts Ops · Runbooks                    │
└────────────────┬────────────────────────────┘
                 │ provisiona
     ┌───────────┼───────────┐
     ▼           ▼           ▼
  [BeeAI]    [BoviPro]    [IAI] ...
  deploy      deploy      deploy
  apenas      apenas      apenas
```

Uma infra mínima compartilhada hospeda todas as aplicações no **mesmo cluster AKS**, **mesmo PostgreSQL** (databases isolados) e **mesmo ACR**. Cada app tem seu próprio namespace K8s e Key Vault.

**Custo atual:** ~$97/mês (vs ~$268/mês com infras separadas)

---

## Estrutura

```
Infra/
├── bootstrap/                  # Executar 1x: cria tfstate storage + RG plataforma
│   └── main.tf
│
├── modules/                    # Módulos Terraform reutilizáveis (Azure)
│   ├── aks/                    # AKS cluster + node pools + RBAC
│   ├── acr/                    # Container Registry
│   ├── network/                # VNet + Subnets + NSGs
│   ├── postgres/               # PostgreSQL Flexible Server + DNS privado
│   ├── keyvault/               # Key Vault + RBAC
│   ├── observability/          # Log Analytics + App Insights + Action Group
│   └── ai/                     # Azure OpenAI + Content Safety
│
├── envs/
│   └── shared-dev/             # ★ Ambiente ativo — rg-shared-dev (East US 2)
│       ├── main.tf             # Recursos compartilhados + por app
│       ├── variables.tf
│       ├── outputs.tf
│       ├── backend.tf          # State: stbeeaitfstategrw1t4/tfstate/shared-dev
│       ├── providers.tf
│       └── shared-dev.tfvars
│
├── k8s/                        # Manifests Kubernetes de todas as apps
│   ├── beeai/                  # namespace, network-policy, api, ai-service, web, gateway
│   └── bovipro/                # namespace, network-policy, api, web, gateway
│
├── scripts/
│   ├── ops-check.sh            # Health check rápido de toda a plataforma
│   ├── rollback.sh             # Rollback de deploy de qualquer app
│   └── add-app.sh              # Checklist para adicionar nova aplicação
│
├── .github/workflows/
│   ├── infra-apply-shared-dev.yml  # Apply infra (push em envs/** ou modules/**)
│   ├── infra-plan.yml              # Plan em PRs
│   └── infra-destroy.yml           # Destroy manual (requer confirmação)
│
├── DevOps.md                   # Manual completo de operações
└── README.md                   # Este arquivo
```

---

## Infra Atual (shared-dev)

| Recurso | Nome | Detalhes |
|---|---|---|
| Resource Group | `rg-shared-dev` | East US 2 |
| AKS | `aks-shared-dev` | 1x Standard_D2s_v3, K8s 1.32 |
| ACR | `acrheckiodev` | Basic, `acrheckiodev.azurecr.io` |
| PostgreSQL | `psql-heckio-dev` | B_Standard_B1ms, DBs: beeai + bovipro |
| KV BeeAI | `kv-beeai-shareddev` | CSI Driver, rotação 2min |
| KV BoviPro | `kv-bovipro-dev` | CSI Driver, rotação 2min |
| Azure OpenAI | `oai-beeai-shareddev` | GPT-4o + GPT-4o-mini |
| Content Safety | `cs-beeai-shareddev` | |
| Log Analytics | `law-shared-dev` | 30 dias |
| App Insights | `appi-shared-dev` | |

---

## Comandos Rápidos

```bash
# Conectar ao cluster
az aks get-credentials --resource-group rg-shared-dev --name aks-shared-dev --admin

# Status de toda a plataforma
./scripts/ops-check.sh

# Apply da infra (manual)
cd envs/shared-dev
MSYS_NO_PATHCONV=1 TF_VAR_pg_admin_password="BeeAiDev2025!" \
  terraform apply -var-file="shared-dev.tfvars"

# Rollback de uma app
./scripts/rollback.sh beeai-api
./scripts/rollback.sh bovipro-api

# Checklist para nova app
./scripts/add-app.sh novaapp
```

---

## Adicionando Nova Aplicação

1. Editar `envs/shared-dev/main.tf` — adicionar database, KV, RBAC e connection string
2. Criar manifests em `k8s/<novaapp>/`
3. No repo da app: criar apenas `.github/workflows/deploy-dev.yml`
4. Configurar GitHub Secrets no repo da app apontando para `acrheckiodev` / `aks-shared-dev`

Detalhes: `./scripts/add-app.sh <nome>` ou seção 11 do `DevOps.md`.

---

## O que NÃO fica aqui

- Código das aplicações (BeeAI, BoviPro, IAI)
- Testes unitários / E2E das aplicações
- Dockerfiles e docker-compose das aplicações
- Workflows de **deploy** das aplicações (ficam nos repos de cada app)
