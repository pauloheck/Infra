# Infra — Plataforma _heck

> **Fonte única de verdade para toda a infraestrutura compartilhada.**
> As aplicações (BeeAI, BoviPro, IAI) fazem **apenas deploy** — não gerenciam infraestrutura.

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
  [BeeAI]    [BoviPro]    [IAI]
  deploy      deploy      deploy
  apenas      apenas      apenas
```

Uma infra compartilhada hospeda todas as aplicações no **mesmo cluster AKS**, **mesmo PostgreSQL** (databases isolados) e **mesmo ACR**. Cada app tem seu próprio namespace K8s e Key Vault. Ambientes **DEV** e **PROD** separados por namespaces (`{app}-dev`, `{app}-prod`) e Key Vaults, na mesma infraestrutura.

**Custo estimado:** ~$114/mês (3 apps x 2 ambientes)

---

## Estratégia de Ambientes

| App | Branch Dev | Branch Prod | Namespace Dev | Namespace Prod |
|-----|-----------|-------------|---------------|----------------|
| BeeAI | `dev` | `main` | `beeai-dev` | `beeai-prod` |
| BoviPro | `dev` | `main` | `bovipro-dev` | `bovipro-prod` |
| IAI | `dev` | `main` | `iai-dev` | `iai-prod` |

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
│   └── shared-dev/             # Ambiente unificado (gerencia DEV + PROD)
│       ├── main.tf             # Recursos compartilhados + por app + prod
│       ├── variables.tf
│       ├── outputs.tf
│       ├── backend.tf
│       ├── providers.tf
│       └── shared-dev.tfvars
│
├── k8s/                        # Manifests Kubernetes de todas as apps
│   ├── beeai-dev/              # BeeAI dev: api, ai-service, web, gateway
│   ├── beeai-prod/             # BeeAI prod
│   ├── bovipro-dev/            # BoviPro dev: api, web, gateway
│   ├── bovipro-prod/           # BoviPro prod
│   ├── iai-dev/                # IAI dev: core (LoadBalancer direto)
│   └── iai-prod/               # IAI prod
│
├── scripts/
│   ├── ops-check.sh            # Health check de toda a plataforma (6 namespaces)
│   ├── rollback.sh             # Rollback de deploy de qualquer app/ambiente
│   └── add-app.sh              # Checklist para adicionar nova aplicação
│
├── .github/workflows/
│   ├── infra-apply.yml         # Apply infra (push em envs/** ou modules/**)
│   ├── infra-plan.yml          # Plan em PRs
│   └── infra-destroy.yml       # Destroy manual (requer confirmação)
│
├── DevOps.md                   # Manual completo de operações
└── README.md                   # Este arquivo
```

---

## Recursos Provisionados

| Recurso | Nome | Detalhes |
|---|---|---|
| Resource Group | `rg-shared-dev` | East US 2 |
| AKS | `aks-shared-dev` | 1x Standard_D2s_v3, K8s 1.32 |
| ACR | `acrheckiodev` | Basic, `acrheckiodev.azurecr.io` |
| PostgreSQL | `psql-heckio-dev` | B1ms, DBs: beeai, bovipro, iai, beeai-prod, bovipro-prod, iai-prod |
| KV BeeAI (dev) | `kv-beeai-shareddev` | CSI Driver |
| KV BeeAI (prod) | `kv-beeai-prod` | CSI Driver |
| KV BoviPro (dev) | `kv-bovipro-dev` | CSI Driver |
| KV BoviPro (prod) | `kv-bovipro-prod` | CSI Driver |
| KV IAI (dev) | `kv-iai-shareddev` | CSI Driver |
| KV IAI (prod) | `kv-iai-prod` | CSI Driver |
| Azure OpenAI (BeeAI) | `oai-beeai-shareddev` | GPT-4o + GPT-4o-mini |
| Azure OpenAI (IAI) | `oai-iai-dev` | GPT-4o-mini |
| Content Safety | `cs-beeai-shareddev` | BeeAI only |
| Log Analytics | `law-shared-dev` | 30 dias |
| App Insights | `appi-shared-dev` | Compartilhado |

---

## Comandos Rápidos

```bash
# Conectar ao cluster
az aks get-credentials --resource-group rg-shared-dev --name aks-shared-dev --admin

# Status de toda a plataforma
./scripts/ops-check.sh

# Apply da infra (manual)
cd envs/shared-dev
TF_VAR_pg_admin_password="<senha>" TF_VAR_iai_device_token="<token>" \
  terraform apply -var-file="shared-dev.tfvars"

# Rollback de uma app
./scripts/rollback.sh beeai-dev beeai-api
./scripts/rollback.sh bovipro-prod bovipro-api

# Checklist para nova app
./scripts/add-app.sh novaapp
```

---

## Adicionando Nova Aplicação

1. Editar `envs/shared-dev/main.tf` — adicionar database, KV, RBAC e secrets (dev + prod)
2. Criar manifests em `k8s/<app>-dev/` e `k8s/<app>-prod/`
3. No repo da app: criar `.github/workflows/deploy-dev.yml` e `deploy-prod.yml`
4. Configurar GitHub Secrets nos environments `dev` e `production`

Detalhes: `./scripts/add-app.sh <nome>` ou `DevOps.md`.

---

## O que NÃO fica aqui

- Código das aplicações (BeeAI, BoviPro, IAI)
- Testes unitários / E2E das aplicações
- Dockerfiles e docker-compose das aplicações
- Workflows de **deploy** das aplicações (ficam nos repos de cada app)
