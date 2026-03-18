# DevOps Manual — Plataforma _heck

> **Infraestrutura única compartilhada para todas as aplicações do ecossistema _heck.**
> Aplicações atuais: **BeeAI** e **BoviPro**
>
> Status atual (2026-03-18): **rg-shared-dev CRIADO e operacional.**

---

## Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Estado Atual da Infraestrutura](#2-estado-atual-da-infraestrutura)
3. [Pré-requisitos e Ferramentas](#3-pré-requisitos-e-ferramentas)
4. [Estrutura de Repositórios](#4-estrutura-de-repositórios)
5. [Terraform — Provisionamento e Gestão](#5-terraform--provisionamento-e-gestão)
6. [Kubernetes — AKS e Namespaces](#6-kubernetes--aks-e-namespaces)
7. [Key Vault e Gestão de Secrets](#7-key-vault-e-gestão-de-secrets)
8. [CI/CD — GitHub Actions](#8-cicd--github-actions)
9. [Desenvolvimento Local](#9-desenvolvimento-local)
10. [Runbooks Operacionais](#10-runbooks-operacionais)
11. [Adicionando uma Nova Aplicação](#11-adicionando-uma-nova-aplicação)
12. [Gestão de Custos](#12-gestão-de-custos)
13. [Segurança](#13-segurança)
14. [Troubleshooting](#14-troubleshooting)
15. [Referências Rápidas](#15-referências-rápidas)

---

## 1. Visão Geral da Arquitetura

### Princípio Central

**Uma infraestrutura mínima compartilhada** hospeda todas as aplicações _heck durante a fase de construção. Cada aplicação roda em seu próprio namespace Kubernetes isolado, mas compartilha o cluster, o banco de dados (servidor único, databases separados), o container registry e o workspace de observabilidade.

### Diagrama

```
┌──────────────────────────────────────────────────────────────────────┐
│                    Azure East US 2 — rg-shared-dev                   │
│                                                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │        AKS — aks-shared-dev (1 nó Standard_D2s_v3)           │    │
│  │                                                                │    │
│  │  ┌─────────────────────────┐  ┌─────────────────────────┐    │    │
│  │  │   namespace: beeai       │  │   namespace: bovipro     │    │    │
│  │  │                          │  │                          │    │    │
│  │  │  beeai-gateway           │  │  bovipro-gateway         │    │    │
│  │  │  [LoadBalancer] ◄── IP₁  │  │  [LoadBalancer] ◄── IP₂  │    │    │
│  │  │    ↓                     │  │    ↓                     │    │    │
│  │  │  beeai-api  :8000        │  │  bovipro-api   :8080     │    │    │
│  │  │  beeai-ai   :8001        │  │  bovipro-web   :3000     │    │    │
│  │  │  beeai-web  :3000        │  │                          │    │    │
│  │  └─────────────────────────┘  └─────────────────────────┘    │    │
│  │                                                                │    │
│  │  NetworkPolicy: isolamento total entre namespaces              │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                        │
│  ┌─────────────────────┐  ┌─────────────────────┐                    │
│  │  psql-heckio-dev     │  │  acrheckiodev        │                   │
│  │  ├── db: beeai       │  │  ├── beeai-api       │                   │
│  │  └── db: bovipro     │  │  ├── beeai-ai        │                   │
│  │  B_Standard_B1ms     │  │  ├── beeai-web       │                   │
│  └─────────────────────┘  │  ├── bovipro-api      │                   │
│                            │  └── bovipro-web      │                   │
│  ┌─────────────────────┐  └─────────────────────┘                    │
│  │  kv-beeai-shareddev  │                                              │
│  │  kv-bovipro-dev      │  ┌─────────────────────┐                   │
│  │  (RBAC, CSI Driver)  │  │  law-shared-dev      │                   │
│  └─────────────────────┘  │  appi-shared-dev      │                   │
│                            │  (30 dias retenção)  │                   │
│  ┌─────────────────────┐  └─────────────────────┘                    │
│  │  oai-beeai-shareddev │                                              │
│  │  cs-beeai-shareddev  │  (somente BeeAI usa IA)                     │
│  └─────────────────────┘                                              │
└──────────────────────────────────────────────────────────────────────┘
```

### Recursos Azure

| Recurso | Nome | Propósito |
|---|---|---|
| Resource Group | `rg-shared-dev` | Contém todos os recursos compartilhados |
| AKS | `aks-shared-dev` | Cluster único, 1 nó D2s_v3 |
| ACR | `acrheckiodev` | Registry de imagens Docker |
| PostgreSQL | `psql-heckio-dev` | Servidor único, múltiplos databases |
| Key Vault BeeAI | `kv-beeai-shareddev` | Secrets exclusivos BeeAI |
| Key Vault BoviPro | `kv-bovipro-dev` | Secrets exclusivos BoviPro |
| Log Analytics | `law-shared-dev` | Logs centralizados (30 dias) |
| App Insights | `appi-shared-dev` | Telemetria de aplicação |
| Azure OpenAI | `oai-beeai-shareddev` | GPT-4o + GPT-4o-mini (BeeAI) |
| Content Safety | `cs-beeai-shareddev` | Moderação de conteúdo (BeeAI) |

### Custo Estimado (fase de construção)

| Recurso | SKU | Custo/mês |
|---|---|---|
| AKS — 1 nó | Standard_D2s_v3 (2vCPU/8GB) | ~$70 |
| PostgreSQL | B_Standard_B1ms | ~$15 |
| ACR Basic | Basic | ~$5 |
| Key Vault ×2 | Standard | ~$2 |
| Log Analytics | PerGB2018 (30 dias) | ~$5 |
| Azure OpenAI | Pay-per-token | variável |
| **Total fixo** | | **~$97/mês** |

> **Nota:** Standard_B2ms (~$42/mês) não possui quota de AKS nesta subscription em East US 2. Usando D2s_v3 que é confirmadamente disponível. Para reduzir custo futuro, solicitar quota B2ms via suporte Azure.

---

## 2. Estado Atual da Infraestrutura

### rg-shared-dev (CRIADO — 2026-03-18)

```
✅ rg-shared-dev               (East US 2)
✅ vnet-shared-dev              (10.10.0.0/16)
✅ aks-shared-dev               (1x D2s_v3, FQDN: aks-shared-dev-wvgwfkpq.hcp.eastus2.azmk8s.io)
✅ acrheckiodev                 (acrheckiodev.azurecr.io)
✅ psql-heckio-dev              (psql-heckio-dev.postgres.database.azure.com, DBs: beeai + bovipro)
✅ kv-beeai-shareddev           (secrets: pg-connection-string, jwt-secret-key, ai-foundry-*, appinsights-*)
✅ kv-bovipro-dev               (secrets: bovipro-pg-connection, bovipro-jwt-secret)
✅ oai-beeai-shareddev          (endpoint: https://oai-beeai-shareddev.openai.azure.com/)
✅ cs-beeai-shareddev
✅ law-shared-dev + appi-shared-dev
```

### Infras Legadas (ainda rodando — DESTRUIR após validação)

```
⚠️  rg-beeai-dev    (AKS antigo BeeAI — ~$200/mês)
⚠️  rg-bovipro-dev  (App Service BoviPro — ~$15/mês)
```

### GitHub Secrets (já atualizados em ambos os repos)

```
Repositórios: pauloheck/BeeAI  e  pauloheck/BOVIPRO  (environment: dev)

ACR_NAME           = acrheckiodev
AKS_NAME           = aks-shared-dev
AKS_RESOURCE_GROUP = rg-shared-dev
```

### Pendências para Ativar os Apps

- [ ] Executar pipeline BeeAI: `gh workflow run deploy-dev.yml --repo pauloheck/BeeAI --ref main`
- [ ] Executar pipeline BoviPro: `gh workflow run ci-deploy-dev.yml --repo pauloheck/BOVIPRO --ref dev`
- [ ] Validar BeeAI: obter IP do `beeai-gateway` e testar `/health/ready`
- [ ] Validar BoviPro: obter IP do `bovipro-gateway` e testar `/api/health`
- [ ] Destruir infras antigas (ver RB-06)

---

## 3. Pré-requisitos e Ferramentas

### Ferramentas Necessárias

```bash
# Azure CLI
az --version                    # >= 2.55.0

# Terraform
terraform --version             # >= 1.6.0

# kubectl
kubectl version --client        # >= 1.28

# GitHub CLI
gh --version

# Docker (para builds locais)
docker --version
```

### Instalação (Windows via winget)

```powershell
winget install Microsoft.AzureCLI
winget install Hashicorp.Terraform
winget install Kubernetes.kubectl
winget install GitHub.cli
winget install Docker.DockerDesktop
```

> **Atenção Windows (Git Bash):** Sempre usar `MSYS_NO_PATHCONV=1` antes de comandos Terraform para evitar conversão incorreta de paths.

### Autenticação Azure

```bash
# Login interativo
az login

# Definir subscription
az account set --subscription "797403f4-3d34-4417-99c3-154e6129693f"

# Verificar identidade ativa
az account show --query "{name:name, id:id, user:user.name}" -o table
```

### Acesso ao Cluster (AKS)

```bash
# Obter credenciais admin
az aks get-credentials \
  --resource-group rg-shared-dev \
  --name aks-shared-dev \
  --admin \
  --overwrite-existing

# Verificar
kubectl get nodes
kubectl get pods -A
```

---

## 4. Estrutura de Repositórios

> **Princípio:** `C:/_heck/Infra/` é a fonte única de verdade para toda a infra.
> As aplicações contêm apenas código e workflows de **deploy**.

```
C:/_heck/
│
├── Infra/                          # ★ FONTE DA VERDADE — Toda infraestrutura ★
│   ├── bootstrap/                  # tfstate storage + RG plataforma (executar 1x)
│   ├── modules/                    # Módulos Terraform reutilizáveis
│   │   ├── aks/                    # AKS (suporta enable_user_pool=false)
│   │   ├── acr/                    # Container Registry (suporta name_override)
│   │   ├── network/                # VNet + Subnets + NSGs
│   │   ├── postgres/               # PostgreSQL (suporta server_name_override)
│   │   ├── keyvault/               # Key Vault (suporta name_override)
│   │   ├── observability/          # Log Analytics + App Insights
│   │   └── ai/                     # Azure OpenAI + Content Safety
│   ├── envs/
│   │   └── shared-dev/             # ★ Ambiente ativo — rg-shared-dev
│   ├── k8s/
│   │   ├── beeai/                  # Manifests K8s BeeAI
│   │   └── bovipro/                # Manifests K8s BoviPro
│   ├── scripts/
│   │   ├── ops-check.sh            # Health check de toda a plataforma
│   │   ├── rollback.sh             # Rollback de deploy
│   │   └── add-app.sh              # Checklist para nova app
│   ├── .github/workflows/
│   │   ├── infra-apply-shared-dev.yml
│   │   ├── infra-plan.yml
│   │   └── infra-destroy.yml
│   └── DevOps.md                   # ← Este documento
│
├── BeeAI/                          # Código da aplicação BeeAI (deploy only)
│   ├── apps/
│   │   ├── api/                    # FastAPI backend Python
│   │   ├── web/                    # Next.js 15 frontend
│   │   ├── ai-service/             # LangGraph AI service
│   │   └── workers/
│   ├── docker-compose.yml          # Ambiente local
│   └── .github/workflows/
│       ├── deploy-dev.yml          # ★ Deploy BeeAI → shared AKS
│       └── deploy-prd.yml          # Deploy produção (manual)
│
├── BOVIPRO/
│   └── bovipro-infra/              # Código da aplicação BoviPro (deploy only)
│       ├── bovipro-backend/        # Rust/Axum API
│       ├── bovipro-frontend/       # Next.js 14 frontend
│       └── .github/workflows/
│           └── ci-deploy-dev.yml   # ★ Deploy BoviPro → shared AKS
│
└── IAI/                            # Código da aplicação IAI (deploy only)
    └── .github/workflows/
        └── deploy-dev.yml          # Deploy IAI → shared AKS (futuro)
```

---

## 5. Terraform — Provisionamento e Gestão

### Terraform State (remoto)

```
Storage Account : stbeeaitfstategrw1t4
Resource Group  : rg-beeai-platform
Container       : tfstate
Key             : shared-dev/terraform.tfstate
```

### Variáveis do Ambiente Atual

| Variável | Valor real deployado | Descrição |
|---|---|---|
| `project` | `shared` | Prefixo padrão |
| `env` | `dev` | Ambiente |
| `location` | `eastus2` | Região Azure |
| `system_vm_size` | `Standard_D2s_v3` | VM do nó AKS (B2ms sem quota nesta sub) |
| `system_node_count` | `1` | 1 nó único |
| `enable_user_pool` | `false` | Workloads rodam no pool system |
| `pg_sku` | `B_Standard_B1ms` | PostgreSQL burstable mínimo |
| `log_retention_days` | `30` | Mínimo do SKU PerGB2018 |

### Overrides de Nome (nomes padrão já em uso globalmente)

| Recurso | Nome padrão (colide) | Nome real deployado |
|---|---|---|
| ACR | `acrshareddev` | `acrheckiodev` |
| PostgreSQL | `psql-shared-dev` | `psql-heckio-dev` |
| KV BeeAI | `kv-beeai-dev` | `kv-beeai-shareddev` |
| Azure OpenAI | `oai-beeai-dev` | `oai-beeai-shareddev` |
| Content Safety | `cs-beeai-dev` | `cs-beeai-shareddev` |

Esses overrides estão configurados em `infra/envs/shared-dev/main.tf` via variáveis `name_override` / `server_name_override` / `openai_name_override` dos módulos.

### Apply do Zero (se for recriar)

```bash
cd C:/_heck/Infra/envs/shared-dev

# 1. Inicializar backend remoto
terraform init

# 2. Verificar plano
MSYS_NO_PATHCONV=1 \
TF_VAR_pg_admin_password="BeeAiDev2025!" \
terraform plan -var-file="shared-dev.tfvars"

# 3. Aplicar
MSYS_NO_PATHCONV=1 \
TF_VAR_pg_admin_password="BeeAiDev2025!" \
terraform apply -var-file="shared-dev.tfvars" -auto-approve

# 4. Criar secrets JWT (não gerados pelo Terraform)
az keyvault secret set \
  --vault-name kv-beeai-shareddev \
  --name jwt-secret-key \
  --value "$(openssl rand -base64 48)"

az keyvault secret set \
  --vault-name kv-bovipro-dev \
  --name bovipro-jwt-secret \
  --value "$(openssl rand -base64 48)"
```

### Verificar Outputs

```bash
cd C:/_heck/Infra/envs/shared-dev
MSYS_NO_PATHCONV=1 terraform output
```

Saída esperada:
```
aks_name           = "aks-shared-dev"
aks_fqdn           = "aks-shared-dev-wvgwfkpq.hcp.eastus2.azmk8s.io"
acr_name           = "acrheckiodev"
acr_login_server   = "acrheckiodev.azurecr.io"
postgres_fqdn      = "psql-heckio-dev.postgres.database.azure.com"
kv_beeai_name      = "kv-beeai-shareddev"
kv_bovipro_name    = "kv-bovipro-dev"
openai_endpoint    = "https://oai-beeai-shareddev.openai.azure.com/"
resource_group_name = "rg-shared-dev"
```

### Apply via GitHub Actions (recomendado em CI)

O workflow `infra-apply-shared-dev.yml` dispara automaticamente quando há push em:
- `infra/envs/shared-dev/**`
- `infra/modules/**`

```bash
# Trigger manual
gh workflow run infra-apply-shared-dev.yml --repo pauloheck/BeeAI --ref main
```

### Destruir Ambiente

```bash
# ATENÇÃO: Irreversível. Apaga TODOS os recursos do rg-shared-dev.
cd C:/_heck/Infra/envs/shared-dev
MSYS_NO_PATHCONV=1 \
TF_VAR_pg_admin_password="BeeAiDev2025!" \
terraform destroy -var-file="shared-dev.tfvars"
```

---

## 6. Kubernetes — AKS e Namespaces

### Namespaces

| Namespace | Aplicação | Services |
|---|---|---|
| `beeai` | BeeAI Platform | api, ai-service, web, gateway |
| `bovipro` | BoviPro | api, web, gateway |

### Estrutura de Cada Aplicação no AKS

```
namespace/<app>/
├── Deployment         → pods, imagem, recursos, probes, volumes CSI
├── Service            → ClusterIP interno (gateway = LoadBalancer)
├── ConfigMap          → variáveis não-sensíveis (APP_ENV, RUST_LOG, etc.)
└── SecretProviderClass → leitura de secrets do Azure Key Vault via CSI
```

### Gateway Pattern

Cada aplicação tem seu próprio NGINX gateway como único ponto público:

```
Internet → LoadBalancer IP (público) → NGINX Gateway → Services internos (ClusterIP)
```

| App | Service gateway | Tipo | Acesso público |
|---|---|---|---|
| BeeAI | `beeai-gateway` | LoadBalancer | `http://<IP_BEEAI>` |
| BoviPro | `bovipro-gateway` | LoadBalancer | `http://<IP_BOVIPRO>` |

Todos os outros services (`beeai-api`, `beeai-ai`, `beeai-web`, `bovipro-api`, `bovipro-web`) são ClusterIP — sem IP externo.

### Obter IPs dos Gateways

```bash
# IPs de todos os LoadBalancers
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,IP:.status.loadBalancer.ingress[0].ip"

# IP específico BeeAI
kubectl get svc beeai-gateway -n beeai \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# IP específico BoviPro
kubectl get svc bovipro-gateway -n bovipro \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Roteamento NGINX — BeeAI

```nginx
/mcp/*                   → beeai-ai:8001    (MCP tools, rate limit 10/min)
/orgs/*/ai/*             → beeai-ai:8001    (SSE chat, proxy_buffering off, timeout 600s)
/auth|/me|/orgs|/health  → beeai-api:8000
/gateway-health          → 200 OK direto    (K8s liveness probe do gateway)
/                        → beeai-web:3000
```

### Roteamento NGINX — BoviPro

```nginx
/api/*          → bovipro-api:8080  (rewrite: strip prefixo /api antes de encaminhar)
/gateway-health → 200 OK direto     (K8s liveness probe do gateway)
/               → bovipro-web:3000
```

> O frontend BoviPro é buildado com `NEXT_PUBLIC_API_BASE_URL=http://<GATEWAY_IP>/api`. O browser chama `http://<IP>/api/<rota>` e o NGINX faz rewrite para `/<rota>` antes de encaminhar ao Rust backend na porta 8080.

### Network Policy (Isolamento)

Cada namespace tem NetworkPolicy aplicando menor privilégio:
- API/Web só aceita tráfego do gateway do mesmo namespace
- Gateway aceita tráfego externo (0.0.0.0/0) na porta 80
- Egress liberado (para Azure OpenAI, Key Vault, PostgreSQL, ACR)
- Pods do namespace `beeai` não podem se comunicar com pods do namespace `bovipro`

### Recursos por Pod

| Pod | CPU Request/Limit | RAM Request/Limit |
|---|---|---|
| beeai-api | 250m / 1000m | 256Mi / 512Mi |
| beeai-ai | 250m / 1000m | 256Mi / 512Mi |
| beeai-web | 100m / 500m | 128Mi / 256Mi |
| beeai-gateway | 50m / 200m | 64Mi / 128Mi |
| bovipro-api | 100m / 500m | 128Mi / 256Mi |
| bovipro-web | 100m / 500m | 128Mi / 256Mi |
| bovipro-gateway | 50m / 200m | 64Mi / 128Mi |

Total máximo: ~1.0 vCPU / 2.0 GB RAM (cabe confortavelmente no D2s_v3 com 2vCPU/8GB).

### Comandos kubectl Úteis

```bash
# Status geral
kubectl get pods -A
kubectl get all -n beeai
kubectl get all -n bovipro

# Logs
kubectl logs -n beeai deployment/beeai-api --follow
kubectl logs -n bovipro deployment/bovipro-api --tail=100
kubectl logs -n beeai deployment/beeai-gateway

# Debug
kubectl exec -it -n beeai deployment/beeai-api -- /bin/sh
kubectl describe pod -n bovipro -l app=bovipro-api

# Verificar secrets injetados pelo CSI
kubectl get secret -n beeai beeai-secrets -o jsonpath='{.data.JWT_SECRET_KEY}' | base64 -d

# Forçar re-deploy (após update de configmap ou secret)
kubectl rollout restart deployment/beeai-api -n beeai
kubectl rollout status deployment/beeai-api -n beeai
```

---

## 7. Key Vault e Gestão de Secrets

### Key Vaults

| KV | App | Secrets armazenados |
|---|---|---|
| `kv-beeai-shareddev` | BeeAI | `pg-connection-string`, `jwt-secret-key`, `ai-foundry-endpoint`, `content-safety-endpoint`, `ai-foundry-deployment-dev`, `ai-foundry-deployment-prod`, `appinsights-connection-string` |
| `kv-bovipro-dev` | BoviPro | `bovipro-pg-connection`, `bovipro-jwt-secret` |

### Como os Secrets chegam aos Pods

O fluxo usa **CSI Secret Store Driver** + **Azure Key Vault Provider**:

```
Azure Key Vault
      ↓
SecretProviderClass (ops/k8s/<app>/api/secret-provider.yaml)
      ↓
CSI Volume montado no pod (/mnt/secrets-store)
      ↓
K8s Secret criado automaticamente (beeai-secrets / bovipro-secrets)
      ↓
Env vars injetadas no container via secretKeyRef
```

O CSI Driver verifica atualizações no Key Vault a cada **2 minutos** (`secret_rotation_interval = "2m"`). Quando um secret é atualizado no KV, os pods recebem o novo valor sem restart.

### Criar / Atualizar Secrets Manualmente

```bash
# BeeAI — JWT Secret Key
az keyvault secret set \
  --vault-name kv-beeai-shareddev \
  --name jwt-secret-key \
  --value "<jwt-secret-min-32-chars>"

# BoviPro — JWT Secret
az keyvault secret set \
  --vault-name kv-bovipro-dev \
  --name bovipro-jwt-secret \
  --value "<jwt-secret>"

# Verificar metadados sem revelar o valor
az keyvault secret show \
  --vault-name kv-beeai-shareddev \
  --name jwt-secret-key \
  --query "attributes.{created:created, updated:updated, enabled:enabled}" \
  -o table
```

### Acesso ao PostgreSQL

```bash
# Obter connection string do KV
az keyvault secret show \
  --vault-name kv-beeai-shareddev \
  --name pg-connection-string \
  --query value -o tsv

# Acesso via pod temporário no AKS (PostgreSQL é privado — sem acesso público)
kubectl run psql-tmp --rm -it \
  --image=postgres:16-alpine \
  --namespace=beeai \
  -- psql "postgresql://pgadmin:BeeAiDev2025!@psql-heckio-dev.postgres.database.azure.com/beeai?sslmode=require"
```

---

## 8. CI/CD — GitHub Actions

### Workflows Ativos

| Workflow | Repo | Trigger | O que faz |
|---|---|---|---|
| `infra-apply-shared-dev.yml` | BeeAI | Push `infra/**` ou manual | Terraform apply shared-dev |
| `deploy-dev.yml` | BeeAI | Push `apps/**` em main | Deploy BeeAI no shared AKS |
| `ci-deploy-dev.yml` | BoviPro | Push em `dev` ou manual | Deploy BoviPro no shared AKS |
| `deploy-prd.yml` | BeeAI | Manual (workflow_dispatch) | Deploy BeeAI em produção |

### Autenticação OIDC (sem senhas armazenadas)

Ambos os repos usam **Workload Identity Federation** — sem client secrets guardados no GitHub:

```yaml
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### App Registrations OIDC

| Repo | App Registration | Client ID |
|---|---|---|
| pauloheck/BeeAI | `beeai-github-oidc` | `5e7d2204-f730-42ff-af20-29eaabca2ae3` |
| pauloheck/BOVIPRO | `bovipro-github-actions` | `ac67b3bb-d8c7-4264-bd3e-f086500ccc11` |

### GitHub Secrets por Repo

| Secret | BeeAI | BoviPro | Onde configurar |
|---|---|---|---|
| `AZURE_CLIENT_ID` | `5e7d2204-...` | `ac67b3bb-...` | repo-level |
| `AZURE_TENANT_ID` | `7377a982-...` | `7377a982-...` | repo-level |
| `AZURE_SUBSCRIPTION_ID` | `797403f4-...` | `797403f4-...` | repo-level |
| `ACR_NAME` | `acrheckiodev` | `acrheckiodev` | env: dev |
| `AKS_NAME` | `aks-shared-dev` | `aks-shared-dev` | env: dev |
| `AKS_RESOURCE_GROUP` | `rg-shared-dev` | `rg-shared-dev` | env: dev |
| `TF_VAR_pg_admin_password` | `BeeAiDev2025!` | — | env: dev (só BeeAI) |

### Configurar / Atualizar GitHub Secrets via CLI

```bash
# BeeAI — environment dev
gh secret set ACR_NAME --body "acrheckiodev" --repo pauloheck/BeeAI --env dev
gh secret set AKS_NAME --body "aks-shared-dev" --repo pauloheck/BeeAI --env dev
gh secret set AKS_RESOURCE_GROUP --body "rg-shared-dev" --repo pauloheck/BeeAI --env dev

# BoviPro — environment dev
gh secret set ACR_NAME --body "acrheckiodev" --repo pauloheck/BOVIPRO --env dev
gh secret set AKS_NAME --body "aks-shared-dev" --repo pauloheck/BOVIPRO --env dev
gh secret set AKS_RESOURCE_GROUP --body "rg-shared-dev" --repo pauloheck/BOVIPRO --env dev
```

### Fluxo de Deploy BeeAI (4 jobs)

```
Push main (apps/**)
        │
        ▼
[Job 1] build-api-ai
  - Docker build beeai-api + beeai-ai
  - Push para acrheckiodev.azurecr.io
        │
        ▼
[Job 2] deploy-api-ai
  - kubectl apply namespace, configs, secrets, network-policy
  - Deploy beeai-api + beeai-ai + beeai-gateway
  - Aguarda LoadBalancer IP do beeai-gateway (max 5 min)
        │
        ▼
[Job 3] build-web
  - Docker build beeai-web com:
    NEXT_PUBLIC_API_URL=http://<GATEWAY_IP>
    NEXT_PUBLIC_AI_URL=http://<GATEWAY_IP>
  - Push para acrheckiodev.azurecr.io
        │
        ▼
[Job 4] deploy-web
  - kubectl apply beeai-web
  - Rollback automático em caso de falha
```

### Fluxo de Deploy BoviPro (4 jobs)

```
Push branch dev
        │
        ▼
[Job 1] build-api
  - Docker build bovipro-api (Rust)
  - Push para acrheckiodev.azurecr.io
        │
        ▼
[Job 2] deploy-api
  - kubectl apply namespace bovipro, configs, secrets, network-policy
  - Deploy bovipro-api + bovipro-gateway
  - Aguarda LoadBalancer IP do bovipro-gateway
        │
        ▼
[Job 3] build-web
  - Docker build bovipro-web (Next.js 14) com:
    NEXT_PUBLIC_API_BASE_URL=http://<GATEWAY_IP>/api
  - Push para acrheckiodev.azurecr.io
        │
        ▼
[Job 4] deploy-web
  - kubectl apply bovipro-web
  - Rollback automático em caso de falha
```

### Executar Pipelines Manualmente

```bash
# BeeAI — deploy completo
gh workflow run deploy-dev.yml --repo pauloheck/BeeAI --ref main

# BoviPro — deploy completo
gh workflow run ci-deploy-dev.yml --repo pauloheck/BOVIPRO --ref dev

# Infra — terraform apply
gh workflow run infra-apply-shared-dev.yml --repo pauloheck/BeeAI --ref main

# Monitorar execução
gh run list --repo pauloheck/BeeAI --workflow deploy-dev.yml
gh run view <run-id> --log --repo pauloheck/BeeAI
```

---

## 9. Desenvolvimento Local

### BeeAI — Docker Compose

```bash
cd C:/_heck/BeeAI
docker compose up --build -d

# Verificar saúde
curl http://localhost:6010/health/ready   # API
curl http://localhost:6040/health/live    # AI Service
```

| Serviço | URL | Observação |
|---|---|---|
| Gateway | http://localhost:6080 | Entry point recomendado |
| API | http://localhost:6010 | Docs: /docs |
| AI Service | http://localhost:6040 | Docs: /docs |
| Frontend | http://localhost:6030 | |
| PostgreSQL | localhost:6020 | user: beeaiadmin / beeailocal |

Credenciais padrão: `admin@beeai.io` / `AdminPassword123!`

### BoviPro — Docker Compose

```bash
cd C:/_heck/BOVIPRO/bovipro-infra
docker compose up --build -d
```

| Serviço | URL |
|---|---|
| API Rust | http://localhost:8080 |
| Frontend | http://localhost:3002 |
| PostgreSQL | localhost:5432 (bovipro / bovipro123) |

---

## 10. Runbooks Operacionais

### RB-01: Executar Deploy das Apps no shared-dev (PRÓXIMA AÇÃO)

A infra está criada. Para ativar as apps:

```bash
# 1. Obter credenciais AKS
az aks get-credentials \
  --resource-group rg-shared-dev \
  --name aks-shared-dev \
  --admin

# 2. Verificar cluster
kubectl get nodes

# 3. Disparar pipeline BeeAI
gh workflow run deploy-dev.yml --repo pauloheck/BeeAI --ref main

# 4. Acompanhar deploy BeeAI
gh run list --repo pauloheck/BeeAI --workflow deploy-dev.yml --limit 1

# 5. Após BeeAI OK, disparar BoviPro
gh workflow run ci-deploy-dev.yml --repo pauloheck/BOVIPRO --ref dev

# 6. Verificar pods e IPs
kubectl get pods -A
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,IP:.status.loadBalancer.ingress[0].ip"
```

### RB-02: Deploy Manual de Emergência (sem pipeline)

```bash
# Autenticar no ACR
az acr login --name acrheckiodev

# BeeAI API — trocar imagem
kubectl set image deployment/beeai-api \
  api=acrheckiodev.azurecr.io/beeai-api:<TAG> \
  --namespace beeai
kubectl rollout status deployment/beeai-api --namespace beeai --timeout=5m

# BoviPro API — trocar imagem
kubectl set image deployment/bovipro-api \
  api=acrheckiodev.azurecr.io/bovipro-api:<TAG> \
  --namespace bovipro
kubectl rollout status deployment/bovipro-api --namespace bovipro --timeout=5m
```

### RB-03: Rollback de Deploy

```bash
# Verificar histórico
kubectl rollout history deployment/beeai-api --namespace beeai

# Rollback para versão anterior
kubectl rollout undo deployment/beeai-api --namespace beeai

# Rollback para revisão específica
kubectl rollout undo deployment/beeai-api --to-revision=2 --namespace beeai

# Confirmar rollback
kubectl rollout status deployment/beeai-api --namespace beeai
```

### RB-04: Escalar Nó do AKS

```bash
# Ver nós atuais e uso
kubectl get nodes
kubectl top nodes

# Escalar para 2 nós (se carga aumentar)
az aks nodepool scale \
  --resource-group rg-shared-dev \
  --cluster-name aks-shared-dev \
  --name system \
  --node-count 2

# Verificar
kubectl get nodes
```

### RB-05: Verificar Logs de Aplicação

```bash
# BeeAI — últimas 100 linhas
kubectl logs -n beeai deployment/beeai-api --tail=100
kubectl logs -n beeai deployment/beeai-ai --tail=100

# BoviPro — follow em tempo real
kubectl logs -n bovipro deployment/bovipro-api --follow

# Filtrar por erros
kubectl logs -n beeai deployment/beeai-api | grep -i "error\|exception\|traceback"

# Logs do gateway (NGINX access log)
kubectl logs -n beeai deployment/beeai-gateway

# Eventos recentes com warnings
kubectl get events -n beeai --sort-by='.lastTimestamp' | tail -20
kubectl get events -n bovipro --sort-by='.lastTimestamp' | tail -20
```

### RB-06: Destruir Infras Legadas (economizar ~$215/mês)

**Pré-requisito:** Validar que ambas as apps estão funcionando no shared-dev.

```bash
# Confirmar que shared-dev está OK
kubectl get pods -n beeai
kubectl get pods -n bovipro

# Verificar IPs dos gateways respondendo
BEEAI_IP=$(kubectl get svc beeai-gateway -n beeai -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -f "http://$BEEAI_IP/health/ready" && echo "BeeAI OK"

BOVIPRO_IP=$(kubectl get svc bovipro-gateway -n bovipro -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -f "http://$BOVIPRO_IP/api/health" && echo "BoviPro OK"

# Destruir infras legadas (IRREVERSÍVEL)
az group delete --name rg-beeai-dev --yes --no-wait
az group delete --name rg-bovipro-dev --yes --no-wait

# Verificar resultado (aguardar alguns minutos)
az group list --query "[?contains(name,'dev')].[name, location]" -o table
```

### RB-07: Acesso Direto ao PostgreSQL

O PostgreSQL está em VNet privada — sem acesso público. Acesso via pod temporário no AKS:

```bash
# Database BeeAI
kubectl run psql-debug \
  --rm -it \
  --image=postgres:16-alpine \
  --namespace=beeai \
  -- psql "postgresql://pgadmin:BeeAiDev2025!@psql-heckio-dev.postgres.database.azure.com/beeai?sslmode=require"

# Database BoviPro
kubectl run psql-debug \
  --rm -it \
  --image=postgres:16-alpine \
  --namespace=bovipro \
  -- psql "postgresql://pgadmin:BeeAiDev2025!@psql-heckio-dev.postgres.database.azure.com/bovipro?sslmode=require"

# Comandos psql úteis
\l          # listar databases
\dt         # listar tabelas
\d users    # descrever tabela
\q          # sair
```

### RB-08: Verificar Custo e Recursos Ativos

```bash
# Recursos do shared-dev
az resource list --resource-group rg-shared-dev \
  --query "[].{name:name, type:type}" -o table

# Node pools e VMs do AKS
az aks nodepool list \
  --resource-group rg-shared-dev \
  --cluster-name aks-shared-dev \
  --query "[].{name:name, count:count, vmSize:vmSize, mode:mode}" \
  -o table

# Todos os resource groups (identificar legados ainda ativos)
az group list --query "[?contains(name,'beeai') || contains(name,'bovipro') || contains(name,'shared') || contains(name,'heck')].[name, location]" -o table
```

### RB-09: Rotacionar Senhas e Secrets

```bash
# Gerar novo JWT secret para BeeAI
NEW_SECRET=$(openssl rand -base64 48)
az keyvault secret set \
  --vault-name kv-beeai-shareddev \
  --name jwt-secret-key \
  --value "$NEW_SECRET"
# O CSI Driver atualiza o pod em até 2 minutos automaticamente

# Rotacionar JWT BoviPro
az keyvault secret set \
  --vault-name kv-bovipro-dev \
  --name bovipro-jwt-secret \
  --value "$(openssl rand -base64 48)"

# Forçar re-leitura imediata (se não quiser aguardar 2 min)
kubectl rollout restart deployment/beeai-api -n beeai
kubectl rollout restart deployment/bovipro-api -n bovipro
```

---

## 11. Adicionando uma Nova Aplicação

### Passo 1: Database no PostgreSQL

Em `infra/envs/shared-dev/main.tf`, adicionar:

```hcl
resource "azurerm_postgresql_flexible_server_database" "novaapp" {
  name      = "novaapp"
  server_id = module.postgres.server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
```

### Passo 2: Key Vault para a nova app

```hcl
module "kv_novaapp" {
  source = "../../modules/keyvault"

  project             = "novaapp"
  env                 = var.env
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_diagnostics  = false
  # name_override     = "kv-novaapp-shareddev"  # usar se kv-novaapp-dev já existir globalmente
  depends_on          = [module.aks]
}

# RBAC: AKS lê o KV
resource "azurerm_role_assignment" "aks_kv_novaapp" {
  scope                            = module.kv_novaapp.key_vault_id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.aks.aks_identity_principal_id
  skip_service_principal_aad_check = true
}

# RBAC: Terraform grava no KV durante apply
resource "azurerm_role_assignment" "terraform_kv_novaapp" {
  scope                = module.kv_novaapp.key_vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
  lifecycle { ignore_changes = [principal_id] }
}

# Connection string no KV
resource "azurerm_key_vault_secret" "novaapp_pg_connection" {
  name         = "novaapp-pg-connection"
  value        = "postgresql://pgadmin:${var.pg_admin_password}@${module.postgres.server_fqdn}:5432/novaapp?sslmode=require"
  key_vault_id = module.kv_novaapp.key_vault_id
  depends_on   = [module.kv_novaapp, module.postgres, azurerm_role_assignment.terraform_kv_novaapp]
}
```

### Passo 3: Manifests Kubernetes

Criar em `Infra/k8s/<novaapp>/`:

```
ops/k8s/
├── namespace.yaml           # namespace: novaapp
├── network-policy.yaml      # mesma estrutura de beeai/bovipro
├── api/
│   ├── deployment.yaml      # imagem, porta, recursos, probes
│   ├── service.yaml         # ClusterIP
│   ├── configmap.yaml       # env vars não-sensíveis
│   └── secret-provider.yaml # keyvaultName: kv-novaapp-dev
├── web/                     # se houver frontend
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── gateway/
    ├── deployment.yaml      # nginx:1.27-alpine
    ├── service.yaml         # LoadBalancer
    └── configmap.yaml       # roteamento NGINX
```

### Passo 4: CI/CD

Criar `.github/workflows/deploy-dev.yml` seguindo o padrão BeeAI/BoviPro:
- `ACR_NAME` → `acrheckiodev`
- `AKS_NAME` → `aks-shared-dev`
- `AKS_RESOURCE_GROUP` → `rg-shared-dev`
- Namespace K8s → `novaapp`
- Imagens → `acrheckiodev.azurecr.io/novaapp-api:latest`

### Passo 5: Configurar OIDC e Aplicar

```bash
# Criar App Registration OIDC para o novo repo (se for repo separado)
az ad app create --display-name "novaapp-github-oidc"

# Apply Terraform (a partir do diretório Infra/)
cd C:/_heck/Infra/envs/shared-dev
MSYS_NO_PATHCONV=1 TF_VAR_pg_admin_password="BeeAiDev2025!" \
terraform apply -var-file="shared-dev.tfvars"

# Criar JWT secret
az keyvault secret set \
  --vault-name kv-novaapp-dev \
  --name novaapp-jwt-secret \
  --value "$(openssl rand -base64 48)"

# Configurar GitHub Secrets e rodar pipeline
gh secret set ACR_NAME --body "acrheckiodev" --repo pauloheck/NOVAAPP --env dev
gh secret set AKS_NAME --body "aks-shared-dev" --repo pauloheck/NOVAAPP --env dev
gh secret set AKS_RESOURCE_GROUP --body "rg-shared-dev" --repo pauloheck/NOVAAPP --env dev
```

---

## 12. Gestão de Custos

### Orçamento Atual (shared-dev)

| Recurso | SKU | ~Custo/mês |
|---|---|---|
| AKS — 1 nó D2s_v3 | Standard_D2s_v3 | $70 |
| PostgreSQL | B_Standard_B1ms | $15 |
| ACR Basic | Basic | $5 |
| Key Vault ×2 | Standard | $2 |
| Log Analytics | PerGB2018, 30 dias | $5 |
| Azure OpenAI | Pay-per-token | variável |
| **Total fixo** | | **~$97/mês** |

**Comparação:** Antes da consolidação, as duas infras separadas custavam ~$268/mês (AKS com 3x D2s_v3 + App Service). Economia atual: ~$171/mês.

**Oportunidade futura:** Solicitar quota para Standard_B2ms (~$42/mês) via suporte Azure. Economia adicional de ~$28/mês.

### Regras para Manter Custo Baixo

1. **Nunca habilitar Container Insights** em dev (`enable_container_insights = false`)
2. **Logs 30 dias** em dev (mínimo do SKU PerGB2018 — não aumentar)
3. **Sem user pool no AKS** (`enable_user_pool = false`)
4. **Sem HA no PostgreSQL** (`high_availability = false`)
5. **Sem geo-redundant backup** (`geo_redundant_backup = false`)
6. **ACR Basic** (sem geo-replication)
7. **Destruir infras antigas** após validar que apps funcionam no shared-dev
8. **Monitorar AzureDiagnostics**: usar apenas `kube-audit-admin` (não `kube-audit`)

### Quando Escalar (produção)

Ao criar `infra/envs/prd/` (não usar shared-dev para produção):

| Recurso | Dev | Prd |
|---|---|---|
| AKS system | 1× D2s_v3 | 2× D4s_v5 |
| AKS user pool | desabilitado | 2-5× D8s_v5 (autoscale) |
| PostgreSQL | B_B1ms | GP_D2s_v3 + HA |
| ACR | Basic | Premium |
| Log retention | 30 dias | 90 dias |
| Geo-redundant backup | off | on |

### Alerta de Budget

```bash
# Criar budget de $120/mês para rg-shared-dev (com 20% de folga)
az consumption budget create \
  --budget-name "shared-dev-budget" \
  --amount 120 \
  --time-grain Monthly \
  --resource-group rg-shared-dev \
  --start-date "2026-04-01" \
  --end-date "2027-04-01"
```

---

## 13. Segurança

### Princípios Aplicados

| Princípio | Implementação |
|---|---|
| Zero Trust | NetworkPolicy: cada pod aceita somente de quem precisa |
| Menor privilégio | RBAC por escopo mínimo (KV por app, AcrPull no AKS) |
| Secrets em KV | Nunca em ConfigMaps, variáveis de ambiente hardcoded, ou código |
| OIDC sem senhas | GitHub Actions usa Workload Identity Federation |
| Imagens privadas | ACR sem acesso público (`admin_enabled = false`) |
| Postgres privado | VNet integration, sem `public_network_access` |
| Rotação automática | CSI Driver verifica KV a cada 2 minutos |

### RBAC Azure (papéis atribuídos)

| Principal | Escopo | Role |
|---|---|---|
| AKS kubelet identity | `kv-beeai-shareddev` | Key Vault Secrets Officer |
| AKS kubelet identity | `kv-bovipro-dev` | Key Vault Secrets Officer |
| AKS kubelet identity | `oai-beeai-shareddev` | Cognitive Services OpenAI User |
| AKS kubelet identity | `cs-beeai-shareddev` | Cognitive Services User |
| AKS kubelet identity | `acrheckiodev` | AcrPull |
| BeeAI GitHub Actions SP | subscription | Contributor |
| BeeAI GitHub Actions SP | `aks-shared-dev` | AKS Cluster Admin Role |
| BoviPro GitHub Actions SP | `aks-shared-dev` | AKS Cluster Admin Role |
| BoviPro GitHub Actions SP | `acrheckiodev` | AcrPush |

### O que NUNCA fazer

- Commitar senhas, keys ou connection strings com credenciais reais
- Usar `admin_enabled = true` no ACR
- Expor PostgreSQL publicamente (`public_network_access_enabled = true`)
- Armazenar secrets em ConfigMaps (usar SecretProviderClass + CSI)
- Remover NetworkPolicy dos namespaces
- Usar `--no-verify` ou `--validate=false` em kubectl

---

## 14. Troubleshooting

### Pod em CrashLoopBackOff

```bash
# Logs do crash anterior
kubectl logs -n <namespace> <pod-name> --previous

# Eventos do pod
kubectl describe pod -n <namespace> <pod-name>

# Causas comuns:
# 1. Secret não encontrado → verificar SecretProviderClass e nome do KV
# 2. DB connection refused → verificar string de conexão e VNet
# 3. Porta errada → conferir containerPort no deployment vs porta real da app
# 4. Probe falhando → verificar path da probe (/health/live vs /health)
```

### Secret não Injetado pelo CSI Driver

```bash
# Verificar se SecretProviderClass foi aplicada
kubectl get secretproviderclass -n <namespace>

# Verificar se o pod tem o volume montado
kubectl describe pod -n <namespace> <pod-name> | grep -A10 "Volumes"

# Logs do CSI driver (procurar erros de permissão)
kubectl logs -n kube-system -l app=secrets-store-csi-driver --tail=50

# Problema comum: nome do KV incorreto no secret-provider.yaml
# BeeAI usa kv-beeai-shareddev (não kv-beeai-dev)
kubectl get secretproviderclass -n beeai beeai-kv-secrets -o yaml | grep keyvaultName
```

### Gateway sem IP Público (LoadBalancer Pending)

```bash
# Verificar status
kubectl get svc -n <namespace> <app>-gateway

# Aguardar com watch
kubectl get svc -n <namespace> <app>-gateway --watch

# Se persistir por mais de 5 min: verificar quota de IPs públicos
az network public-ip list \
  --resource-group MC_rg-shared-dev_aks-shared-dev_eastus2 \
  -o table
```

### Pipeline CI/CD Falhou

```bash
# Ver runs recentes
gh run list --repo pauloheck/BeeAI --workflow deploy-dev.yml --limit 5

# Ver logs completos de um run
gh run view <run-id> --log --repo pauloheck/BeeAI

# Causas comuns:
# 1. "unauthorized" no ACR → verificar AZURE_CLIENT_ID e role AcrPush/AcrPull
# 2. "Forbidden" no kubectl → verificar AKS Cluster Admin Role no SP
# 3. Rollout timeout → ver logs do pod (probe falhando, OOM, etc.)
# 4. "acrshareddev not found" → secrets ainda apontam para nome antigo
```

### PostgreSQL — Migrations não Aplicadas (BoviPro)

```bash
# BoviPro usa SQLx auto-migrations no startup
# Ver logs de startup
kubectl logs -n bovipro deployment/bovipro-api --previous

# Se migrations falharam por permissão, conectar e aplicar manualmente
kubectl run migrate --rm -it \
  --image=acrheckiodev.azurecr.io/bovipro-api:latest \
  --namespace=bovipro \
  --env="DATABASE_URL=postgresql://pgadmin:BeeAiDev2025!@psql-heckio-dev.postgres.database.azure.com/bovipro?sslmode=require" \
  -- /app/bovipro-api --migrate-only
```

### Nó AKS com Pressão de Memória (OOMKilled)

```bash
# Verificar uso atual
kubectl top nodes
kubectl top pods -A --sort-by=memory

# Eventos OOM
kubectl get events -A | grep -i "oom\|killed\|memory"

# Reduzir temporariamente: reiniciar AI service (maior consumidor)
kubectl rollout restart deployment/beeai-ai -n beeai

# Solução definitiva: escalar para 2 nós (ver RB-04)
# Ou solicitar quota para D4s_v3 (4vCPU/16GB) e fazer resize
```

### Verificar Quota de VM para AKS

```bash
# Listar VMs disponíveis para AKS em eastus2 (para trocar de D2s_v3 para B2ms quando quota permitir)
az vm list-skus --location eastus2 --size Standard_B --output table \
  --query "[?restrictions[0].reasonCode == null || !restrictions].{Name:name}" 2>/dev/null | head -20

# Solicitar aumento de quota: portal.azure.com → Subscriptions → Usage + quotas
```

---

## 15. Referências Rápidas

### Comandos de Status Rápido

```bash
# Status completo da plataforma
kubectl get pods -A -o wide

# IPs públicos dos gateways
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,IP:.status.loadBalancer.ingress[0].ip"

# Uso de recursos
kubectl top nodes && kubectl top pods -A

# Warnings recentes
kubectl get events -A --field-selector type=Warning \
  --sort-by='.lastTimestamp' | tail -20

# Versão do Kubernetes
kubectl version --short
```

### Acessar Apps

```bash
# BeeAI
BEEAI_IP=$(kubectl get svc beeai-gateway -n beeai -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "BeeAI URL: http://$BEEAI_IP"
curl "http://$BEEAI_IP/health/ready"

# BoviPro
BOVIPRO_IP=$(kubectl get svc bovipro-gateway -n bovipro -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "BoviPro URL: http://$BOVIPRO_IP"
curl "http://$BOVIPRO_IP/api/health"
```

### Configurações de Referência

```
Subscription     : 797403f4-3d34-4417-99c3-154e6129693f
Tenant           : 7377a982-cbdf-40d4-af3d-281d65c00164
Resource Group   : rg-shared-dev (East US 2)
AKS              : aks-shared-dev (1x Standard_D2s_v3, FQDN: aks-shared-dev-wvgwfkpq.hcp.eastus2.azmk8s.io)
ACR              : acrheckiodev.azurecr.io
PostgreSQL       : psql-heckio-dev.postgres.database.azure.com (admin: pgadmin)
KV BeeAI         : kv-beeai-shareddev
KV BoviPro       : kv-bovipro-dev
Azure OpenAI     : https://oai-beeai-shareddev.openai.azure.com/
TF State         : stbeeaitfstategrw1t4 / tfstate / shared-dev/terraform.tfstate
DB Password      : BeeAiDev2025!  ← reutilizado do ambiente legado
```

### App Registrations (OIDC)

```
BeeAI CI/CD    : beeai-github-oidc   (5e7d2204-f730-42ff-af20-29eaabca2ae3)
BoviPro CI/CD  : bovipro-github-actions (ac67b3bb-d8c7-4264-bd3e-f086500ccc11)
```

### Checklist Pós-Terraform Apply

- [x] `rg-shared-dev` criado com todos os recursos
- [x] AKS com 1 nó D2s_v3 funcionando
- [x] `jwt-secret-key` criado em `kv-beeai-shareddev`
- [x] `bovipro-jwt-secret` criado em `kv-bovipro-dev`
- [x] GitHub Secrets atualizados nos dois repos (env: dev)
- [x] BoviPro SP recebeu AKS Cluster Admin Role + AcrPush
- [ ] Pipeline BeeAI executada com sucesso
- [ ] Pipeline BoviPro executada com sucesso
- [ ] IPs dos dois gateways obtidos e testados
- [ ] Health checks funcionando em ambos (`/health/ready` e `/api/health`)
- [ ] Infras antigas destruídas (`rg-beeai-dev`, `rg-bovipro-dev`)

---

*Última atualização: 2026-03-18 | Infraestrutura: rg-shared-dev ATIVA | Fonte da verdade: C:/_heck/Infra/*
