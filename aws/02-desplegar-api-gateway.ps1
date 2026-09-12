<#
.SINOPSIS
    Crea la HTTP API de AWS API Gateway con JWT Authorizer de Microsoft Entra ID,
    todas las rutas funcionales y las rutas OPTIONS publicas. Idempotente.

.DESCRIPCION
    Reemplaza los ~40 clics de la consola por un comando reproducible. Si lo vuelves
    a ejecutar, reutiliza la API existente y solo crea lo que falte.

.EJEMPLO
    .\02-desplegar-api-gateway.ps1 -DestinoBff "http://54.210.11.22:8080"

.EJEMPLO
    .\02-desplegar-api-gateway.ps1 -DestinoBff "https://abc-def.trycloudflare.com" -CorsEnGateway
#>
[CmdletBinding()]
param(
    # URL base publica donde escucha el BFF. SIN barra final.
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https?://[^/]+$')]
    [string]$DestinoBff,

    [string]$Region = "us-east-1",

    [string]$NombreApi = "API_Gateway_Entrega1",

    # Tenant de Entra ID del equipo.
    [string]$TenantId = "17dd3345-54db-49ce-8172-092f2ccd50fd",

    # Client ID del registro Pedidos360-BACKEND-API. Es el claim 'aud' esperado.
    [string]$Audience = "fc8de29a-f24d-4173-bfc1-12580819e4c7",

    [string]$Stage = '$default',

    # Origenes permitidos para CORS cuando se usa -CorsEnGateway.
    [string[]]$OrigenesPermitidos = @("http://localhost:4200"),

    # Deja que API Gateway responda el preflight por si mismo en vez de reenviar
    # OPTIONS al BFF. Mas robusto, pero se aparta de lo que pide la guia.
    [switch]$CorsEnGateway
)

$ErrorActionPreference = "Stop"

$Issuer = "https://login.microsoftonline.com/$TenantId/v2.0"

function Invoke-Aws {
    param([string[]]$Argumentos, [switch]$PermitirFallo)
    $salida = & aws @Argumentos --region $Region --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($PermitirFallo) { return $null }
        throw "Fallo el comando: aws $($Argumentos -join ' ')`n$salida"
    }
    if ([string]::IsNullOrWhiteSpace($salida)) { return $null }
    return ($salida | Out-String | ConvertFrom-Json)
}

Write-Host ""
Write-Host "=== Despliegue de AWS API Gateway (HTTP API) ===" -ForegroundColor Cyan
Write-Host "  Region     : $Region"
Write-Host "  API        : $NombreApi"
Write-Host "  Destino BFF: $DestinoBff"
Write-Host "  Issuer     : $Issuer"
Write-Host "  Audience   : $Audience"
Write-Host ""

# ---------------------------------------------------------------------------
# 1. API HTTP
# ---------------------------------------------------------------------------

$apis = Invoke-Aws @("apigatewayv2", "get-apis")
$api = $apis.Items | Where-Object { $_.Name -eq $NombreApi } | Select-Object -First 1

if ($api) {
    $apiId = $api.ApiId
    Write-Host "[1/5] API existente reutilizada: $apiId" -ForegroundColor Yellow
} else {
    $argsCrear = @("apigatewayv2", "create-api",
        "--name", $NombreApi,
        "--protocol-type", "HTTP",
        "--description", "EP1 DSY1107 - Punto de entrada unico hacia el BFF Pedidos360")

    if ($CorsEnGateway) {
        $origenes = ($OrigenesPermitidos | ForEach-Object { '"' + $_ + '"' }) -join ","
        $corsJson = '{"AllowOrigins":[' + $origenes + '],' +
                    '"AllowMethods":["GET","POST","PUT","DELETE","OPTIONS"],' +
                    '"AllowHeaders":["authorization","content-type"],' +
                    '"AllowCredentials":false,"MaxAge":3600}'
        $argsCrear += @("--cors-configuration", $corsJson)
    }

    $api = Invoke-Aws $argsCrear
    $apiId = $api.ApiId
    Write-Host "[1/5] API creada: $apiId" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 2. JWT Authorizer
# ---------------------------------------------------------------------------

$nombreAuth = "JWT-EntraID-Authorizer"
$autorizadores = Invoke-Aws @("apigatewayv2", "get-authorizers", "--api-id", $apiId)
$auth = $autorizadores.Items | Where-Object { $_.Name -eq $nombreAuth } | Select-Object -First 1

if ($auth) {
    $authorizerId = $auth.AuthorizerId
    Write-Host "[2/5] Authorizer existente reutilizado: $authorizerId" -ForegroundColor Yellow
} else {
    # Se arma el JSON a mano: ConvertTo-Json en PowerShell 5.1 colapsa los arreglos
    # de un solo elemento a escalar, y Audience debe ser una lista si o si.
    $jwtConfigJson = '{"Audience":["' + $Audience + '"],"Issuer":"' + $Issuer + '"}'

    # IMPORTANTE: NO se pasa --authorization-scopes en las rutas.
    # El authorizer de AWS valida el claim 'scope'; Entra ID emite 'scp'.
    # Exigir el scope aqui produce 403 en absolutamente todas las peticiones.
    # El scope y los roles se validan en el BFF con Spring Security.
    $auth = Invoke-Aws @("apigatewayv2", "create-authorizer",
        "--api-id", $apiId,
        "--name", $nombreAuth,
        "--authorizer-type", "JWT",
        "--identity-source", '$request.header.Authorization',
        "--jwt-configuration", $jwtConfigJson)

    $authorizerId = $auth.AuthorizerId
    Write-Host "[2/5] Authorizer creado: $authorizerId" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. Rutas e integraciones
# ---------------------------------------------------------------------------

$rutasFuncionales = @(
    @{ Metodo = "GET";    Ruta = "/api/orders" },
    @{ Metodo = "POST";   Ruta = "/api/orders" },
    @{ Metodo = "GET";    Ruta = "/api/orders/{id}" },
    @{ Metodo = "PUT";    Ruta = "/api/orders/{id}/accept" },
    @{ Metodo = "PUT";    Ruta = "/api/orders/{id}/prepare" },
    @{ Metodo = "PUT";    Ruta = "/api/orders/{id}/dispatch" },
    @{ Metodo = "PUT";    Ruta = "/api/orders/{id}/deliver" },
    @{ Metodo = "PUT";    Ruta = "/api/orders/{id}/cancel" },
    @{ Metodo = "GET";    Ruta = "/api/catalog" },
    @{ Metodo = "POST";   Ruta = "/api/catalog" },
    @{ Metodo = "GET";    Ruta = "/api/catalog/{id}" },
    @{ Metodo = "PUT";    Ruta = "/api/catalog/{id}" },
    @{ Metodo = "DELETE"; Ruta = "/api/catalog/{id}" }
)

# Preflight. Sin JWT: el navegador no manda Authorization en el OPTIONS, asi que
# protegerlas romperia CORS con un 401 antes de la peticion real.
$rutasPreflight = @(
    @{ Metodo = "OPTIONS"; Ruta = "/api/orders" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/orders/{id}" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/orders/{id}/accept" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/orders/{id}/prepare" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/orders/{id}/dispatch" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/orders/{id}/deliver" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/orders/{id}/cancel" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/catalog" },
    @{ Metodo = "OPTIONS"; Ruta = "/api/catalog/{id}" }
)

$rutasExistentes = (Invoke-Aws @("apigatewayv2", "get-routes", "--api-id", $apiId, "--max-results", "500")).Items
$clavesExistentes = @{}
foreach ($r in $rutasExistentes) { $clavesExistentes[$r.RouteKey] = $r.RouteId }

function Add-Ruta {
    param([string]$Metodo, [string]$Ruta, [bool]$Protegida)

    $claveRuta = "$Metodo $Ruta"
    if ($clavesExistentes.ContainsKey($claveRuta)) {
        Write-Host ("      - {0,-42} (ya existia)" -f $claveRuta) -ForegroundColor DarkGray
        return
    }

    # HTTP APIs sustituyen {id} en la URI de integracion con el valor del path.
    $uriIntegracion = "$script:DestinoBff$Ruta"

    $integracion = Invoke-Aws @("apigatewayv2", "create-integration",
        "--api-id", $script:apiId,
        "--integration-type", "HTTP_PROXY",
        "--integration-method", $Metodo,
        "--integration-uri", $uriIntegracion,
        "--payload-format-version", "1.0")

    $argsRuta = @("apigatewayv2", "create-route",
        "--api-id", $script:apiId,
        "--route-key", $claveRuta,
        "--target", "integrations/$($integracion.IntegrationId)")

    if ($Protegida) {
        $argsRuta += @("--authorization-type", "JWT", "--authorizer-id", $script:authorizerId)
    } else {
        $argsRuta += @("--authorization-type", "NONE")
    }

    Invoke-Aws $argsRuta | Out-Null
    $etiqueta = if ($Protegida) { "JWT" } else { "publica" }
    Write-Host ("      - {0,-42} [{1}]" -f $claveRuta, $etiqueta) -ForegroundColor Green
}

Write-Host "[3/5] Rutas funcionales (protegidas con JWT):"
foreach ($r in $rutasFuncionales) { Add-Ruta -Metodo $r.Metodo -Ruta $r.Ruta -Protegida $true }

if ($CorsEnGateway) {
    Write-Host "[4/5] Preflight resuelto por API Gateway (--cors-configuration). No se crean rutas OPTIONS." -ForegroundColor Yellow
} else {
    Write-Host "[4/5] Rutas OPTIONS (publicas, preflight hacia el BFF):"
    foreach ($r in $rutasPreflight) { Add-Ruta -Metodo $r.Metodo -Ruta $r.Ruta -Protegida $false }
}

# ---------------------------------------------------------------------------
# 4. Stage con auto-deploy
# ---------------------------------------------------------------------------

$stages = Invoke-Aws @("apigatewayv2", "get-stages", "--api-id", $apiId)
$stageExistente = $stages.Items | Where-Object { $_.StageName -eq $Stage } | Select-Object -First 1

if ($stageExistente) {
    Write-Host "[5/5] Stage '$Stage' ya existe." -ForegroundColor Yellow
} else {
    Invoke-Aws @("apigatewayv2", "create-stage",
        "--api-id", $apiId,
        "--stage-name", $Stage,
        "--auto-deploy") | Out-Null
    Write-Host "[5/5] Stage '$Stage' creado con auto-deploy." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 5. Resultado
# ---------------------------------------------------------------------------

$urlInvocacion = "https://$apiId.execute-api.$Region.amazonaws.com"
if ($Stage -ne '$default') { $urlInvocacion = "$urlInvocacion/$Stage" }

$resultado = [ordered]@{
    apiId         = $apiId
    region        = $Region
    nombreApi     = $NombreApi
    authorizerId  = $authorizerId
    stage         = $Stage
    destinoBff    = $DestinoBff
    urlInvocacion = $urlInvocacion
    issuer        = $Issuer
    audience      = $Audience
    generado      = (Get-Date).ToString("s")
}

$rutaSalida = Join-Path $PSScriptRoot "salida-despliegue.json"
$resultado | ConvertTo-Json | Set-Content -Path $rutaSalida -Encoding utf8

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "URL de invocacion publica (esto es lo que le pasas a tu companero" -ForegroundColor Green
Write-Host "para el environment.ts del Angular):" -ForegroundColor Green
Write-Host ""
Write-Host "    $urlInvocacion" -ForegroundColor White
Write-Host ""
Write-Host "Detalle guardado en: $rutaSalida" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Prueba rapida de que el authorizer rechaza sin token (debe dar 401):" -ForegroundColor Cyan
Write-Host "    curl -i $urlInvocacion/api/orders" -ForegroundColor DarkGray
Write-Host ""
