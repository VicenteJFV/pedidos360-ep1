<#
.SINOPSIS
    Carga en el AWS CLI las credenciales temporales del AWS Academy Learner Lab.

.DESCRIPCION
    El Learner Lab entrega credenciales que caducan al terminar la sesion (~4 horas).
    Hay que recargarlas CADA VEZ que inicias el lab, o todos los comandos fallan con
    "ExpiredToken" / "InvalidClientTokenId".

    Donde obtenerlas:
      1. Abre el lab en AWS Academy y presiona "Start Lab" (espera el punto verde).
      2. Click en "AWS Details" -> "AWS CLI" -> "Show".
      3. Copia TODO el bloque, que se ve asi:

           [default]
           aws_access_key_id=ASIA...
           aws_secret_access_key=...
           aws_session_token=...

.EJEMPLO
    .\01-credenciales-learner-lab.ps1
    (pega el bloque, presiona Enter en una linea vacia y listo)

.EJEMPLO
    .\01-credenciales-learner-lab.ps1 -DesdePortapapeles
#>
[CmdletBinding()]
param(
    [switch]$DesdePortapapeles,
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

function Read-BloqueCredenciales {
    if ($DesdePortapapeles) {
        $texto = Get-Clipboard -Raw
        if ([string]::IsNullOrWhiteSpace($texto)) {
            throw "El portapapeles esta vacio. Copia el bloque desde AWS Details -> AWS CLI."
        }
        return $texto
    }

    Write-Host ""
    Write-Host "Pega el bloque de credenciales del Learner Lab y presiona Enter dos veces:" -ForegroundColor Cyan
    Write-Host ""

    $lineas = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $linea = [Console]::In.ReadLine()
        if ($null -eq $linea) { break }
        if ([string]::IsNullOrWhiteSpace($linea) -and $lineas.Count -gt 0) { break }
        if (-not [string]::IsNullOrWhiteSpace($linea)) { $lineas.Add($linea) }
    }
    return ($lineas -join "`n")
}

function Get-Valor {
    param([string]$Texto, [string]$Clave)
    $match = [regex]::Match($Texto, "(?im)^\s*$Clave\s*=\s*(.+?)\s*$")
    if (-not $match.Success) {
        throw "No se encontro '$Clave' en el bloque pegado. Copia el bloque completo desde AWS Details -> AWS CLI."
    }
    return $match.Groups[1].Value.Trim()
}

# ---------------------------------------------------------------------------

$bloque = Read-BloqueCredenciales

$accessKey    = Get-Valor -Texto $bloque -Clave "aws_access_key_id"
$secretKey    = Get-Valor -Texto $bloque -Clave "aws_secret_access_key"
$sessionToken = Get-Valor -Texto $bloque -Clave "aws_session_token"

$carpetaAws = Join-Path $env:USERPROFILE ".aws"
if (-not (Test-Path $carpetaAws)) {
    New-Item -ItemType Directory -Path $carpetaAws | Out-Null
}

$rutaCredenciales = Join-Path $carpetaAws "credentials"
$rutaConfig       = Join-Path $carpetaAws "config"

# Se sobrescribe el perfil default completo: las credenciales del lab son efimeras
# y arrastrar restos de una sesion anterior es la causa numero uno de "ExpiredToken".
$contenidoCredenciales = @"
[default]
aws_access_key_id=$accessKey
aws_secret_access_key=$secretKey
aws_session_token=$sessionToken
"@

$contenidoConfig = @"
[default]
region=$Region
output=json
"@

Set-Content -Path $rutaCredenciales -Value $contenidoCredenciales -Encoding ascii
Set-Content -Path $rutaConfig       -Value $contenidoConfig       -Encoding ascii

Write-Host ""
Write-Host "Credenciales escritas en $rutaCredenciales" -ForegroundColor Green
Write-Host "Region por defecto: $Region" -ForegroundColor Green
Write-Host ""

Write-Host "Verificando identidad..." -ForegroundColor Cyan
$identidad = aws sts get-caller-identity --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "El AWS CLI no pudo autenticarse. Revisa que copiaste el bloque completo y que el lab este iniciado."
}

Write-Host "  Cuenta : $($identidad.Account)" -ForegroundColor Green
Write-Host "  ARN    : $($identidad.Arn)" -ForegroundColor Green
Write-Host ""

# ---------------------------------------------------------------------------
# Diagnostico de limitaciones del Learner Lab
# ---------------------------------------------------------------------------

Write-Host "Comprobando si esta cuenta permite Elastic IP..." -ForegroundColor Cyan
# Se asigna una EIP de prueba y se libera de inmediato: es la unica forma fiable de
# saber si el permission boundary del LabRole lo permite, sin dejar recursos colgando.
$salidaEip = aws ec2 allocate-address --domain vpc --output json 2>&1
if ($LASTEXITCODE -eq 0) {
    $eip = $salidaEip | ConvertFrom-Json
    aws ec2 release-address --allocation-id $eip.AllocationId 2>&1 | Out-Null

    Write-Host "  SI permite Elastic IP (se probo con $($eip.PublicIp) y ya fue liberada)." -ForegroundColor Green
    Write-Host "  Recomendado: asigna una y asociala a la EC2 para tener IP estable." -ForegroundColor Green
    Write-Host "    aws ec2 allocate-address --domain vpc" -ForegroundColor DarkGray
    Write-Host "    aws ec2 associate-address --instance-id <ID> --allocation-id <ALLOC_ID>" -ForegroundColor DarkGray
} else {
    Write-Host "  NO permite Elastic IP en esta cuenta." -ForegroundColor Yellow
    Write-Host "  Respuesta de AWS: $salidaEip" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Consecuencia: la IP publica de la EC2 cambia cada vez que se detiene" -ForegroundColor Yellow
    Write-Host "  y vuelve a iniciar la instancia (o sea, en cada sesion del lab)." -ForegroundColor Yellow
    Write-Host "  Solucion: ejecuta 03-actualizar-destino-bff.ps1 al inicio de cada sesion." -ForegroundColor Yellow
}
Write-Host ""
