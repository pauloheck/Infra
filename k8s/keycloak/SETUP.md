# Keycloak — Setup pós-deploy

## 1. Pré-requisitos Terraform

Antes de aplicar os manifests, o Terraform deve ter criado:
- Key Vault `kv-keycloak-heckdev` com secrets:
  - `keycloak-admin-password` — senha do admin Keycloak
  - `keycloak-db-password` — senha do usuário `keycloak` no PostgreSQL
- Banco de dados `keycloak` no PostgreSQL Flexible Server (`pg-shared-dev`)
- Usuário `keycloak` no PostgreSQL com permissão no banco `keycloak`

Atualizar `secret-provider.yaml` com o `userAssignedIdentityID` do kubelet managed identity:
```bash
az aks show -g rg-shared-dev -n aks-shared-dev --query identityProfile.kubeletidentity.clientId -o tsv
```

## 2. Aplicar manifests

```bash
kubectl apply -f k8s/keycloak/namespace.yaml
kubectl apply -f k8s/keycloak/secret-provider.yaml
kubectl apply -f k8s/keycloak/configmap.yaml
kubectl apply -f k8s/keycloak/deployment.yaml
kubectl apply -f k8s/keycloak/service.yaml
```

## 3. Criar realm "heck"

Aguardar pod ready, depois acessar via port-forward:
```bash
kubectl port-forward -n keycloak svc/keycloak 8080:8080
```

Acesse http://localhost:8080/admin → login admin.

Criar realm:
- Nome: `heck`
- Display Name: `_heck Platform`

## 4. Criar client GetChat

No realm `heck`, criar client:
- Client ID: `getchat`
- Client Protocol: `openid-connect`
- Access Type: `confidential`
- Valid Redirect URIs: `http://localhost:6530/*`, `https://getchat-dev.eastus2.cloudapp.azure.com/*`
- Service Accounts: habilitado

Copiar o `client_secret` e salvar como `keycloak-client-secret` no KV `kv-getchat-dev`.

## 5. Configurar GetChat para usar Keycloak

No KV `kv-getchat-dev` ou ConfigMap do GetChat, definir:
```
KEYCLOAK_URL=http://keycloak.keycloak.svc.cluster.local:8080
KEYCLOAK_REALM=heck
```

O GetChat API (`src/auth.py`) já suporta RS256 via Keycloak JWKS com fallback para HS256 local.

## 6. Criar usuários

No realm `heck` → Users → Create user para cada admin que precisar de acesso.
