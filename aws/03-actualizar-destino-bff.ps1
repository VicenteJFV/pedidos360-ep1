<#
.SINOPSIS
    Re-apunta TODAS las integraciones de la API a una nueva URL base del BFF.

.DESCRIPCION
    En AWS Academy Learner Lab la instancia EC2 se detiene al terminar la sesion y,
    si la cuenta no permite Elastic IP, al reiniciarla recibe una IP publica distinta.
    Sin esto tendrias que editar 22 integraciones a mano en la consola.

    Ejecutalo al inicio de cada sesion del lab, despues de arrancar la EC2.
    Con auto-deploy activo en el stage, el cambio queda vigente al instante.

.EJEMPLO
    .\03-actualizar-destino-bff.ps1 -NuevoDestinoBff "http://54.87.3.190:8080"

.EJEMPLO
    # Toma la IP publica directamente de la instancia, sin copiarla a mano
    .\03-actualizar-destino-bff.ps1 -DesdeInstancia i-0abc123def456
#>
[CmdletBinding(DefaultParameterSetName = "Url")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Url")]
    [ValidatePattern('^https?://[^/]+$')]
    [string]$NuevoDestinoBff,

    [Parameter(Mandatory = $true, ParameterSetName = "Instancia")]
    [string]$DesdeInstancia,

    [Parameter(ParameterSetName = "Instancia")]
    [int]$PuertoBff = 8080,

    [string]$Region = "us-east-1",
    [string]$NombreApi = "API_Gateway_Entrega1"
)

$ErrorActionPreference = "Stop"

function Invoke-Aws {
    param([string[]]$Argumentos)
    $salida = & aws @Argumentos --region $Region --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo el comando: aws $($Argumentos -join ' ')`n$salida"
    }
    if ([string]::IsNullOrWhiteSpace($salida)) { return $null }
    return ($salida | Out-String | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# Resolver el nuevo destino
# ---------------------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq "Instancia") {
    Write-Host "Consultando la IP publica de $DesdeInstancia ..." -ForegroundColor Cyan
    $descripcion = Invoke-Aws @("ec2", "describe-instances", "--instance-ids", $DesdeInstancia)
    $instancia = $descripcion.Reservations[0].Instances[0]

    if ($instancia.State.Name -ne "running") {
        throw "La instancia esta en estado '$($instancia.State.Name)'. Arrancala primero: aws ec2 start-instances --instance-ids $DesdeInstancia"
    }
    if ([string]::IsNullOrWhiteSpace($instancia.PublicIpAddress)) {
        throw "La instancia no tiene IP publica asignada."
    }

    $NuevoDestinoBff = "http://$($instancia.PublicIpAddress):$PuertoBff"
    Write-Host "  IP publica actual: $($instancia.PublicIpAddress)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Nuevo destino del BFF: $NuevoDestinoBff" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Localizar la API
# ---------------------------------------------------------------------------

$apis = Invoke-Aws @("apigatewayv2", "get-apis")
$api = $apis.Items | Where-Object { $_.Name -eq $NombreApi } | Select-Object -First 1
if (-not $api) {
    throw "No se encontro ninguna API llamada '$NombreApi' en $Region. Ejecuta primero 02-desplegar-api-gateway.ps1."
}
$apiId = $api.ApiId

# ---------------------------------------------------------------------------
# Reescribir cada integracion conservando la ruta
# ---------------------------------------------------------------------------

$integraciones = (Invoke-Aws @("apigatewayv2", "get-integrations", "--api-id", $apiId, "--max-results", "500")).Items
if (-not $integraciones) {
    throw "La API $apiId no tiene integraciones. Ejecuta primero 02-desplegar-api-gateway.ps1."
}

$actualizadas = 0
$sinCambio = 0

foreach ($integracion in $integraciones) {
    $uriActual = $integracion.IntegrationUri
    if ([string]::IsNullOrWhiteSpace($uriActual)) { continue }

    # Se conserva todo lo que va despues del host (incluidos los {id}) y se
    # reemplaza solo el esquema + host + puerto.
    $match = [regex]::Match($uriActual, '^https?://[^/]+(?<ruta>/.*)?$')
    if (-not $match.Success) {
        Write-Host "  ! No se pudo interpretar la URI '$uriActual', se omite." -ForegroundColor Yellow
        continue
    }
    $ruta = $match.Groups["ruta"].Value
    $uriNueva = "$NuevoDestinoBff$ruta"

    if ($uriNueva -eq $uriActual) {
        $sinCambio++
        continue
    }

    Invoke-Aws @("apigatewayv2", "update-integration",
        "--api-id", $apiId,
        "--integration-id", $integracion.IntegrationId,
        "--integration-uri", $uriNueva) | Out-Null

    Write-Host ("  {0,-8} {1}" -f $integracion.IntegrationMethod, $uriNueva) -ForegroundColor Green
    $actualizadas++
}

# ---------------------------------------------------------------------------
# Refrescar el archivo de salida y avisar si el stage no tiene auto-deploy
# ---------------------------------------------------------------------------

$rutaSalida = Join-Path $PSScriptRoot "salida-despliegue.json"
if (Test-Path $rutaSalida) {
    $datos = Get-Content $rutaSalida -Raw | ConvertFrom-Json
    $datos.destinoBff = $NuevoDestinoBff
    $datos | ConvertTo-Json | Set-Content -Path $rutaSalida -Encoding utf8
}

$stages = Invoke-Aws @("apigatewayv2", "get-stages", "--api-id", $apiId)
$sinAutoDeploy = $stages.Items | Where-Object { -not $_.AutoDeploy }

Write-Host ""
Write-Host "Integraciones actualizadas: $actualizadas (sin cambios: $sinCambio)" -ForegroundColor Cyan

if ($sinAutoDeploy) {
    Write-Host ""
    Write-Host "ATENCION: estos stages no tienen auto-deploy, hay que desplegar a mano:" -ForegroundColor Yellow
    foreach ($s in $sinAutoDeploy) {
        Write-Host "    aws apigatewayv2 create-deployment --api-id $apiId --stage-name '$($s.StageName)' --region $Region" -ForegroundColor DarkGray
    }
} else {
    Write-Host "Todos los stages tienen auto-deploy: los cambios ya estan vigentes." -ForegroundColor Green
}
Write-Host ""
