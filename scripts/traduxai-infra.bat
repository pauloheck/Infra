@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================================
rem traduxai-infra.bat
rem Provisiona a infra necessaria do Tradux AI no ambiente shared-dev.
rem
rem Responsabilidades:
rem   1. Executar Terraform em envs\shared-dev.
rem   2. Garantir PostgreSQL e AKS ligados para operacao.
rem   3. Aplicar manifests de Keycloak e base Kubernetes do Tradux AI.
rem   4. Opcionalmente aplicar deployments da app com imagens ja publicadas.
rem
rem O deploy normal da aplicacao continua sendo feito pela pipeline GitHub
rem Actions. Use --deploy-app apenas quando quiser aplicar uma tag manualmente.
rem ============================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"
set "TF_DIR=%ROOT%\envs\shared-dev"
set "K8S_TRADUX=%ROOT%\k8s\traduxai-dev"
set "K8S_KEYCLOAK=%ROOT%\k8s\keycloak"
set "ENV_BAT=%SCRIPT_DIR%.env.bat"
set "ENV_SH=%SCRIPT_DIR%.env"

set "RG_NAME=rg-shared-dev"
set "AKS_NAME=aks-shared-dev"
set "PG_NAME=psql-heckio-dev"
set "TFSTATE_RG=rg-beeai-platform"
set "TFSTATE_STORAGE=stbeeaitfstategrw1t4"
set "TFSTATE_CONTAINER=tfstate"
set "TFSTATE_LOCATION=eastus2"
set "TRADUX_DNS_LABEL=traduxai-heck"
set "INGRESS_NGINX_VERSION=controller-v1.15.1"
set "INGRESS_NGINX_MANIFEST=https://raw.githubusercontent.com/kubernetes/ingress-nginx/%INGRESS_NGINX_VERSION%/deploy/static/provider/cloud/deploy.yaml"
if not defined ACR_NAME set "ACR_NAME=acrheckiodev"

set "SKIP_TERRAFORM=0"
set "SKIP_K8S=0"
set "SKIP_KEYCLOAK=0"
set "SKIP_RUNTIME_START=0"
set "SKIP_SECRETS_CHECK=0"
set "PLAN_ONLY=0"
set "APP_DEPLOY=0"
set "USAGE_EXIT=1"

:parse_args
if "%~1"=="" goto after_args
if /I "%~1"=="--help" set "USAGE_EXIT=0"& goto usage
if /I "%~1"=="-h" set "USAGE_EXIT=0"& goto usage
if /I "%~1"=="--skip-terraform" set "SKIP_TERRAFORM=1"& shift & goto parse_args
if /I "%~1"=="--skip-k8s" set "SKIP_K8S=1"& shift & goto parse_args
if /I "%~1"=="--skip-keycloak" set "SKIP_KEYCLOAK=1"& shift & goto parse_args
if /I "%~1"=="--skip-runtime-start" set "SKIP_RUNTIME_START=1"& shift & goto parse_args
if /I "%~1"=="--skip-secrets-check" set "SKIP_SECRETS_CHECK=1"& shift & goto parse_args
if /I "%~1"=="--plan-only" set "PLAN_ONLY=1"& shift & goto parse_args
if /I "%~1"=="--deploy-app" set "APP_DEPLOY=1"& shift & goto parse_args
echo ERRO: argumento desconhecido: %~1
echo.
goto usage

:after_args
if exist "%ENV_BAT%" (
  call "%ENV_BAT%"
) else if exist "%ENV_SH%" (
  call :load_env_sh "%ENV_SH%"
)

if defined TRADUXAI_IMAGE_TAG set "APP_DEPLOY=1"
if "%APP_DEPLOY%"=="1" if not defined TRADUXAI_IMAGE_TAG set "TRADUXAI_IMAGE_TAG=latest"
if not defined ACR_NAME set "ACR_NAME=acrheckiodev"

echo.
echo ============================================================================
echo   Tradux AI - provisionamento de infra shared-dev
echo ============================================================================
echo.

call :require_command az
if errorlevel 1 goto fail
if "%SKIP_TERRAFORM%"=="0" (
  call :require_command terraform
  if errorlevel 1 goto fail
)
if "%SKIP_K8S%"=="0" (
  call :require_command kubectl
  if errorlevel 1 goto fail
)
call :require_command powershell
if errorlevel 1 goto fail

call az account show >nul 2>nul
if errorlevel 1 (
  echo ERRO: Azure CLI nao esta autenticado. Execute: az login
  goto fail
)

if "%SKIP_SECRETS_CHECK%"=="0" (
  call :require_env TF_VAR_pg_admin_password
  if errorlevel 1 goto fail
  call :require_env TF_VAR_iai_device_token
  if errorlevel 1 goto fail
  call :require_env TF_VAR_getchat_anthropic_api_key
  if errorlevel 1 goto fail
)

if not defined TF_VAR_keycloak_admin_password (
  echo AVISO: TF_VAR_keycloak_admin_password nao definido; Terraform usara o default dev.
)
if not defined TF_VAR_traduxai_nextauth_secret (
  echo AVISO: TF_VAR_traduxai_nextauth_secret nao definido; Terraform usara o default dev.
)

if "%SKIP_TERRAFORM%"=="0" (
  echo.
  echo [1/6] Terraform shared-dev
  call :ensure_terraform_backend
  if errorlevel 1 goto fail
  pushd "%TF_DIR%" || goto fail
  terraform init -reconfigure -input=false || goto fail
  call :import_existing_keycloak
  if errorlevel 1 goto fail
  if "%PLAN_ONLY%"=="1" (
    terraform plan -var-file="shared-dev.tfvars" || goto fail
    popd
    echo.
    echo Plano concluido. Nenhuma alteracao foi aplicada por causa de --plan-only.
    goto done
  )
  terraform apply -var-file="shared-dev.tfvars" -auto-approve || goto fail
  popd
) else (
  echo [1/6] Terraform pulado ^(--skip-terraform^)
)

if "%SKIP_RUNTIME_START%"=="0" (
  echo.
  echo [2/6] Garantindo AKS e PostgreSQL ligados
  call :ensure_postgres_running
  if errorlevel 1 goto fail
  call :ensure_aks_running
  if errorlevel 1 goto fail
) else (
  echo [2/6] Start de AKS/PostgreSQL pulado ^(--skip-runtime-start^)
)

if "%SKIP_K8S%"=="1" (
  echo.
  echo [3/6] Kubernetes pulado ^(--skip-k8s^)
  goto done
)

echo.
echo [3/6] Configurando kubectl
call az aks get-credentials --resource-group "%RG_NAME%" --name "%AKS_NAME%" --admin --overwrite-existing || goto fail

set "KUBELET_CLIENT_ID="
for /f "usebackq delims=" %%I in (`call az aks show --resource-group "%RG_NAME%" --name "%AKS_NAME%" --query "identityProfile.kubeletidentity.clientId" -o tsv 2^>nul`) do set "KUBELET_CLIENT_ID=%%I"
if defined KUBELET_CLIENT_ID (
  echo Kubelet managed identity: %KUBELET_CLIENT_ID%
) else (
  echo AVISO: nao consegui obter o clientId da kubelet identity; usarei os manifests como estao.
)

echo.
echo [4/6] Garantindo ingress-nginx compartilhado
call :ensure_ingress_nginx
if errorlevel 1 goto fail

if "%SKIP_KEYCLOAK%"=="0" (
  echo.
  echo [5/6] Aplicando Keycloak compartilhado
  kubectl apply -f "%K8S_KEYCLOAK%\namespace.yaml" || goto fail
  call :apply_secret_provider "%K8S_KEYCLOAK%\secret-provider.yaml"
  if errorlevel 1 goto fail
  kubectl apply -f "%K8S_KEYCLOAK%\configmap.yaml" || goto fail
  kubectl apply -f "%K8S_KEYCLOAK%\service.yaml" || goto fail
  kubectl apply -f "%K8S_KEYCLOAK%\deployment.yaml" || goto fail
  kubectl rollout status deployment/keycloak -n keycloak --timeout=8m
  if errorlevel 1 echo AVISO: Keycloak ainda nao ficou pronto; verifique com kubectl get pods -n keycloak.
) else (
  echo.
  echo [5/6] Keycloak pulado ^(--skip-keycloak^)
)

echo.
echo [6/6] Aplicando base Kubernetes Tradux AI
kubectl apply -f "%K8S_TRADUX%\namespace.yaml" || goto fail
kubectl apply -f "%K8S_TRADUX%\network-policy.yaml" || goto fail
call :apply_secret_provider "%K8S_TRADUX%\api\secret-provider.yaml"
if errorlevel 1 goto fail
kubectl apply -f "%K8S_TRADUX%\api\service.yaml" || goto fail
kubectl apply -f "%K8S_TRADUX%\web\service.yaml" || goto fail
kubectl apply -f "%K8S_TRADUX%\ingress.yaml" || goto fail

if "%APP_DEPLOY%"=="1" (
  call :apply_app_deployments
  if errorlevel 1 goto fail
) else (
  echo.
  echo Deployments da aplicacao nao foram aplicados.
  echo A publicacao de traduxai-api, traduxai-worker e traduxai-web fica pela pipeline GitHub Actions.
  echo Para aplicar manualmente uma imagem ja publicada:
  echo   set TRADUXAI_IMAGE_TAG=MINHA_TAG
  echo   scripts\traduxai-infra.bat --skip-terraform --deploy-app
)

goto done

:usage
echo Uso:
echo   scripts\traduxai-infra.bat
echo   scripts\traduxai-infra.bat --plan-only
echo   scripts\traduxai-infra.bat --skip-terraform
echo   scripts\traduxai-infra.bat --skip-terraform --deploy-app
echo.
echo Variaveis sensiveis:
echo   Preferencialmente copie scripts\.env.bat.example para scripts\.env.bat.
echo   O script tambem tenta ler scripts\.env no formato "export NOME=valor".
echo.
echo Opcoes:
echo   --plan-only            Roda terraform plan e nao aplica nada.
echo   --skip-terraform       Nao roda terraform init/apply.
echo   --skip-k8s             Nao aplica manifests Kubernetes.
echo   --skip-keycloak        Nao aplica manifests Keycloak.
echo   --skip-runtime-start   Nao inicia AKS/PostgreSQL se estiverem parados.
echo   --skip-secrets-check   Nao valida TF_VAR_* obrigatorias antes do Terraform.
echo   --deploy-app           Aplica Deployments da app com ACR_NAME/TRADUXAI_IMAGE_TAG.
exit /b %USAGE_EXIT%

:require_command
where "%~1" >nul 2>nul
if errorlevel 1 (
  echo ERRO: comando obrigatorio nao encontrado no PATH: %~1
  exit /b 1
)
exit /b 0

:require_env
if not defined %~1 (
  echo ERRO: variavel obrigatoria nao definida: %~1
  echo       Defina no ambiente ou em scripts\.env.bat.
  exit /b 1
)
exit /b 0

:load_env_sh
set "LOAD_ENV_FILE=%~1"
echo Lendo variaveis de %LOAD_ENV_FILE% ^(modo compatibilidade^)
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%LOAD_ENV_FILE%") do (
  set "ENV_KEY=%%A"
  set "ENV_VALUE=%%B"
  set "ENV_KEY=!ENV_KEY:export =!"
  for /f "tokens=* delims= " %%K in ("!ENV_KEY!") do set "ENV_KEY=%%K"
  if defined ENV_KEY if defined ENV_VALUE (
    set "ENV_VALUE=!ENV_VALUE:"=!"
    if not defined !ENV_KEY! set "!ENV_KEY!=!ENV_VALUE!"
  )
)
exit /b 0

:ensure_postgres_running
set "PG_STATE="
for /f "usebackq delims=" %%S in (`call az postgres flexible-server show --resource-group "%RG_NAME%" --name "%PG_NAME%" --query "state" -o tsv 2^>nul`) do set "PG_STATE=%%S"
if not defined PG_STATE (
  echo ERRO: PostgreSQL %PG_NAME% nao encontrado em %RG_NAME%.
  exit /b 1
)
echo PostgreSQL %PG_NAME%: %PG_STATE%
if /I "%PG_STATE%"=="Stopped" (
  echo Iniciando PostgreSQL...
  call az postgres flexible-server start --resource-group "%RG_NAME%" --name "%PG_NAME%" || exit /b 1
)
exit /b 0

:ensure_aks_running
set "AKS_STATE="
for /f "usebackq delims=" %%S in (`call az aks show --resource-group "%RG_NAME%" --name "%AKS_NAME%" --query "powerState.code" -o tsv 2^>nul`) do set "AKS_STATE=%%S"
if not defined AKS_STATE (
  echo ERRO: AKS %AKS_NAME% nao encontrado em %RG_NAME%.
  exit /b 1
)
echo AKS %AKS_NAME%: %AKS_STATE%
if /I "%AKS_STATE%"=="Stopped" (
  echo Iniciando AKS...
  call az aks start --resource-group "%RG_NAME%" --name "%AKS_NAME%" || exit /b 1
)
exit /b 0

:ensure_terraform_backend
echo Verificando backend remoto do Terraform...
call az group show --name "%TFSTATE_RG%" >nul 2>nul
if errorlevel 1 (
  echo Criando Resource Group do tfstate: %TFSTATE_RG%
  call az group create --name "%TFSTATE_RG%" --location "%TFSTATE_LOCATION%" --tags project=shared env=dev managedBy=script >nul || exit /b 1
)
call az storage account show --resource-group "%TFSTATE_RG%" --name "%TFSTATE_STORAGE%" >nul 2>nul
if errorlevel 1 (
  echo Criando Storage Account do tfstate: %TFSTATE_STORAGE%
  call az storage account create --resource-group "%TFSTATE_RG%" --name "%TFSTATE_STORAGE%" --location "%TFSTATE_LOCATION%" --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false >nul || exit /b 1
)
call az storage container create --name "%TFSTATE_CONTAINER%" --account-name "%TFSTATE_STORAGE%" --auth-mode login >nul 2>nul
if errorlevel 1 (
  set "TFSTATE_KEY="
  for /f "usebackq delims=" %%K in (`call az storage account keys list --resource-group "%TFSTATE_RG%" --account-name "%TFSTATE_STORAGE%" --query "[0].value" -o tsv 2^>nul`) do set "TFSTATE_KEY=%%K"
  if not defined TFSTATE_KEY (
    echo ERRO: nao consegui obter a chave da Storage Account do tfstate.
    exit /b 1
  )
  call az storage container create --name "%TFSTATE_CONTAINER%" --account-name "%TFSTATE_STORAGE%" --account-key "!TFSTATE_KEY!" >nul || exit /b 1
)
exit /b 0

:import_existing_keycloak
rem Se uma instalacao antiga ja tiver criado estes recursos manualmente,
rem importa para o state antes do apply para evitar conflito de "already exists".
terraform state show module.kv_keycloak.azurerm_key_vault.main >nul 2>nul
if errorlevel 1 (
  set "KV_KEYCLOAK_ID="
  for /f "usebackq delims=" %%I in (`call az keyvault show --resource-group "%RG_NAME%" --name "kv-keycloak-heckdev" --query "id" -o tsv 2^>nul`) do set "KV_KEYCLOAK_ID=%%I"
  if defined KV_KEYCLOAK_ID (
    echo Importando Key Vault existente kv-keycloak-heckdev para o state Terraform...
    terraform import module.kv_keycloak.azurerm_key_vault.main "!KV_KEYCLOAK_ID!" || exit /b 1
  )
)
terraform state show azurerm_postgresql_flexible_server_database.keycloak >nul 2>nul
if errorlevel 1 (
  set "KEYCLOAK_DB_ID="
  for /f "usebackq delims=" %%I in (`call az postgres flexible-server db show --resource-group "%RG_NAME%" --server-name "%PG_NAME%" --database-name "keycloak" --query "id" -o tsv 2^>nul`) do set "KEYCLOAK_DB_ID=%%I"
  if defined KEYCLOAK_DB_ID (
    echo Importando database PostgreSQL existente keycloak para o state Terraform...
    terraform import azurerm_postgresql_flexible_server_database.keycloak "!KEYCLOAK_DB_ID!" || exit /b 1
  )
)
exit /b 0

:apply_secret_provider
set "SPC_IN=%~1"
if not defined KUBELET_CLIENT_ID (
  kubectl apply -f "%SPC_IN%"
  exit /b !ERRORLEVEL!
)
set "SPC_OUT=%TEMP%\traduxai-spc-%RANDOM%%RANDOM%.yaml"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:SPC_IN; $o=$env:SPC_OUT; $id=$env:KUBELET_CLIENT_ID; $q=[char]34; $pattern='userAssignedIdentityID:\s*' + $q + '[^' + $q + ']*' + $q; $replacement='userAssignedIdentityID: ' + $q + $id + $q; $text=Get-Content -LiteralPath $p -Raw; $text=$text -replace $pattern, $replacement; Set-Content -LiteralPath $o -Value $text -Encoding utf8" || exit /b 1
kubectl apply -f "%SPC_OUT%"
set "SPC_STATUS=!ERRORLEVEL!"
del "%SPC_OUT%" >nul 2>nul
exit /b %SPC_STATUS%

:ensure_ingress_nginx
call :discover_ingress_public_ip
if errorlevel 1 exit /b 1

if defined INGRESS_PIP_NAME (
  echo DNS publico %TRADUX_DNS_LABEL%.eastus2.cloudapp.azure.com no IP !INGRESS_PUBLIC_IP!
  call az network public-ip update --resource-group "!AKS_NODE_RG!" --name "!INGRESS_PIP_NAME!" --dns-name "%TRADUX_DNS_LABEL%" --only-show-errors >nul || exit /b 1
) else (
  echo AVISO: nao encontrei Public IP existente do AKS; o Service LoadBalancer pode criar um novo IP.
)

kubectl get ingressclass nginx >nul 2>nul
if errorlevel 1 (
  echo Instalando ingress-nginx %INGRESS_NGINX_VERSION%...
  kubectl apply -f "%INGRESS_NGINX_MANIFEST%" || exit /b 1
) else (
  echo ingressClass nginx ja existe.
)

if defined INGRESS_PUBLIC_IP (
  call :patch_ingress_service_ip
  if errorlevel 1 exit /b 1
)

kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=8m || exit /b 1
kubectl wait --namespace ingress-nginx --for=condition=Ready pod --selector=app.kubernetes.io/component=controller --timeout=8m || exit /b 1
exit /b 0

:discover_ingress_public_ip
set "AKS_NODE_RG="
set "INGRESS_PIP_NAME="
set "INGRESS_PUBLIC_IP="
for /f "usebackq delims=" %%G in (`call az aks show --resource-group "%RG_NAME%" --name "%AKS_NAME%" --query "nodeResourceGroup" -o tsv 2^>nul`) do set "AKS_NODE_RG=%%G"
if not defined AKS_NODE_RG (
  echo ERRO: nao consegui descobrir o resource group gerenciado do AKS.
  exit /b 1
)

for /f "usebackq tokens=1,2" %%A in (`call az network public-ip list --resource-group "!AKS_NODE_RG!" --query "[?dnsSettings.domainNameLabel=='%TRADUX_DNS_LABEL%'] | [0].{name:name,ip:ipAddress}" -o tsv 2^>nul`) do (
  set "INGRESS_PIP_NAME=%%A"
  set "INGRESS_PUBLIC_IP=%%B"
)

if not defined INGRESS_PIP_NAME (
  for /f "usebackq tokens=1,2" %%A in (`call az network public-ip list --resource-group "!AKS_NODE_RG!" --query "[?ipConfiguration!=null] | [0].{name:name,ip:ipAddress}" -o tsv 2^>nul`) do (
    set "INGRESS_PIP_NAME=%%A"
    set "INGRESS_PUBLIC_IP=%%B"
  )
)
exit /b 0

:patch_ingress_service_ip
set "INGRESS_PATCH=%TEMP%\traduxai-ingress-%RANDOM%%RANDOM%.json"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$patch=@{spec=@{loadBalancerIP=$env:INGRESS_PUBLIC_IP}} | ConvertTo-Json -Compress; Set-Content -LiteralPath $env:INGRESS_PATCH -Value $patch -Encoding ascii" || exit /b 1
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type=merge --patch-file "%INGRESS_PATCH%" || exit /b 1
set "PATCH_STATUS=!ERRORLEVEL!"
del "%INGRESS_PATCH%" >nul 2>nul
exit /b %PATCH_STATUS%

:apply_app_deployments
echo.
echo Aplicando Deployments Tradux AI com imagem %ACR_NAME%.azurecr.io/*:%TRADUXAI_IMAGE_TAG%
set "TMP_K8S=%TEMP%\traduxai-k8s-%RANDOM%%RANDOM%"
xcopy "%K8S_TRADUX%" "%TMP_K8S%\" /E /I /Q /Y >nul || exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$root=$env:TMP_K8S; $acr=$env:ACR_NAME + '.azurecr.io'; $tag=$env:TRADUXAI_IMAGE_TAG; $id=$env:KUBELET_CLIENT_ID; $q=[char]34; $pattern='userAssignedIdentityID:\s*' + $q + '[^' + $q + ']*' + $q; $replacement='userAssignedIdentityID: ' + $q + $id + $q; $files=@('api\deployment.yaml','worker\deployment.yaml','web\deployment.yaml','api\secret-provider.yaml'); foreach($f in $files){ $p=Join-Path $root $f; $text=Get-Content -LiteralPath $p -Raw; $text=$text -replace 'ACR_PLACEHOLDER/traduxai-api:latest', ($acr + '/traduxai-api:' + $tag); $text=$text -replace 'ACR_PLACEHOLDER/traduxai-worker:latest', ($acr + '/traduxai-worker:' + $tag); $text=$text -replace 'ACR_PLACEHOLDER/traduxai-web:latest', ($acr + '/traduxai-web:' + $tag); if($id){ $text=$text -replace $pattern, $replacement }; Set-Content -LiteralPath $p -Value $text -Encoding utf8 }" || exit /b 1
kubectl apply -k "%TMP_K8S%" || exit /b 1
kubectl rollout status deployment/traduxai-api -n traduxai-dev --timeout=8m || exit /b 1
kubectl rollout status deployment/traduxai-worker -n traduxai-dev --timeout=8m || exit /b 1
kubectl rollout status deployment/traduxai-web -n traduxai-dev --timeout=8m || exit /b 1
rmdir /S /Q "%TMP_K8S%" >nul 2>nul
exit /b 0

:done
echo.
echo ============================================================================
echo   Infra Tradux AI concluida
echo ============================================================================
echo URL publica esperada: https://traduxai-heck.eastus2.cloudapp.azure.com
echo.
echo Lembrete de custo: ao terminar os trabalhos, pare AKS/PostgreSQL.
echo ============================================================================
exit /b 0

:fail
echo.
echo ERRO: provisionamento interrompido. Veja a mensagem acima.
exit /b 1
