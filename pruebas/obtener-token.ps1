<#
.SINOPSIS
    Obtiene un access token de Microsoft Entra ID y verifica que sirva para el
    JWT Authorizer de AWS API Gateway.

.DESCRIPCION
    Ademas de pedir el token, lo decodifica e inspecciona los claims que deciden
    si API Gateway lo va a aceptar o rechazar. Los tres motivos habituales de 401:

      1. 'iss' es https://sts.windows.net/<tenant>/ en vez de .../v2.0
         -> el registro del backend tiene accessTokenAcceptedVersion en null.
            Debe ser 2. Lo corrige tu companero en el manifiesto de Entra ID.

      2. 'aud' no es el Client ID del backend
         -> se pidio un scope equivocado. Debe ser
            api://<CLIENT_ID_BACKEND>/access_as_user

      3. El scope viaja en 'scp', no en 'scope'
         -> por eso NO hay que configurar Authorization Scopes en API Gateway.

.NOTAS
    Requiere que el registro de aplicacion tenga habilitado "Allow public client
    flows" (Authentication -> Advanced settings). Si tu companero no lo activo,
    ninguno de los dos flujos va a funcionar. Pideselo, o que cree un registro
    aparte tipo public client para pruebas.

.EJEMPLO
    .\obtener-token.ps1 -Usuario "Cliente@luissantacruz2026.onmicrosoft.com"

.EJEMPLO
    .\obtener-token.ps1 -CodigoDispositivo
#>
[CmdletBinding(DefaultParameterSetName = "Password")]
param(
    [Parameter(ParameterSetName = "Password")]
    [string]$Usuario,

    [Parameter(ParameterSetName = "Password")]
    [SecureString]$Password,

    # Flujo device code: abre el navegador. Util si el tenant exige MFA.
    [Parameter(Mandatory = $true, ParameterSetName = "DeviceCode")]
    [switch]$CodigoDispositivo,

    [string]$TenantId = "17dd3345-54db-49ce-8172-092f2ccd50fd",
    [string]$ClientIdFrontend = "6731c641-8037-476d-9d2b-76765ca2ecc3",
    [string]$ClientIdBackend = "fc8de29a-f24d-4173-bfc1-12580819e4c7",

    # Guarda el token en una variable de entorno de la sesion actual.
    [string]$GuardarEnVariable
)

$ErrorActionPreference = "Stop"

$scope = "api://$ClientIdBackend/access_as_user"
$urlToken = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

function ConvertFrom-JwtPayload {
    param([string]$Jwt)
    $partes = $Jwt.Split('.')
    if ($partes.Count -lt 2) { throw "El token no tiene formato JWT." }

    $payload = $partes[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
    }
    $bytes = [Convert]::FromBase64String($payload)
    return [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
}

function Show-Diagnostico {
    param([string]$Jwt)

    $claims = ConvertFrom-JwtPayload -Jwt $Jwt
    $issEsperado = "https://login.microsoftonline.com/$TenantId/v2.0"

    Write-Host ""
    Write-Host "=== Claims del token ===" -ForegroundColor Cyan
    Write-Host ("  iss  : {0}" -f $claims.iss)
    Write-Host ("  aud  : {0}" -f $claims.aud)
    Write-Host ("  scp  : {0}" -f $claims.scp)
    Write-Host ("  roles: {0}" -f ($(if ($claims.roles) { $claims.roles -join ", " } else { "(ninguno)" })))
    Write-Host ("  upn  : {0}" -f $claims.preferred_username)

    $expira = [DateTimeOffset]::FromUnixTimeSeconds([int64]$claims.exp).LocalDateTime
    $minutos = [math]::Round(($expira - (Get-Date)).TotalMinutes)
    Write-Host ("  exp  : {0} (en {1} min)" -f $expira, $minutos)

    Write-Host ""
    Write-Host "=== Compatibilidad con el JWT Authorizer de AWS ===" -ForegroundColor Cyan

    $todoOk = $true

    if ($claims.iss -eq $issEsperado) {
        Write-Host "  [OK]    Issuer coincide con el configurado en API Gateway." -ForegroundColor Green
    } else {
        $todoOk = $false
        Write-Host "  [FALLA] Issuer es '$($claims.iss)'" -ForegroundColor Red
        Write-Host "          API Gateway espera '$issEsperado'" -ForegroundColor Red
        if ($claims.iss -like "https://sts.windows.net/*") {
            Write-Host "          Causa: el token es v1. En el manifiesto del registro" -ForegroundColor Yellow
            Write-Host "          Pedidos360-BACKEND-API hay que poner:" -ForegroundColor Yellow
            Write-Host '            "accessTokenAcceptedVersion": 2' -ForegroundColor Yellow
        }
    }

    if ($claims.aud -eq $ClientIdBackend) {
        Write-Host "  [OK]    Audience coincide con el Client ID del backend." -ForegroundColor Green
    } else {
        $todoOk = $false
        Write-Host "  [FALLA] Audience es '$($claims.aud)', se esperaba '$ClientIdBackend'." -ForegroundColor Red
        Write-Host "          Causa: se pidio un scope distinto de $scope" -ForegroundColor Yellow
    }

    if ($claims.PSObject.Properties.Name -contains "scope") {
        Write-Host "  [OK]    El token trae claim 'scope'." -ForegroundColor Green
    } else {
        Write-Host "  [AVISO] El token trae 'scp', no 'scope'." -ForegroundColor Yellow
        Write-Host "          Es lo normal en Entra ID. Por eso las rutas de API Gateway" -ForegroundColor Yellow
        Write-Host "          NO deben llevar Authorization Scopes: darian 403 siempre." -ForegroundColor Yellow
    }

    Write-Host ""
    if ($todoOk) {
        Write-Host "  Resultado: este token deberia pasar el authorizer." -ForegroundColor Green
    } else {
        Write-Host "  Resultado: este token va a ser rechazado con 401." -ForegroundColor Red
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq "DeviceCode") {

    $urlDevice = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
    $inicio = Invoke-RestMethod -Method Post -Uri $urlDevice -Body @{
        client_id = $ClientIdFrontend
        scope     = "$scope offline_access openid profile"
    }

    Write-Host ""
    Write-Host $inicio.message -ForegroundColor Cyan
    Write-Host ""
    Start-Process $inicio.verification_uri

    $limite = (Get-Date).AddSeconds([int]$inicio.expires_in)
    $respuesta = $null

    while ((Get-Date) -lt $limite) {
        Start-Sleep -Seconds ([int]$inicio.interval)
        try {
            $respuesta = Invoke-RestMethod -Method Post -Uri $urlToken -Body @{
                grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
                client_id   = $ClientIdFrontend
                device_code = $inicio.device_code
            }
            break
        } catch {
            $detalle = $_.ErrorDetails.Message
            if ($detalle -and $detalle -match "authorization_pending") { continue }
            throw "Fallo el device code flow: $detalle"
        }
    }

    if (-not $respuesta) { throw "Se agoto el tiempo esperando la autenticacion." }

} else {

    if (-not $Usuario) {
        $Usuario = Read-Host "Usuario (ej. Cliente@luissantacruz2026.onmicrosoft.com)"
    }
    if (-not $Password) {
        $Password = Read-Host "Contrasena de $Usuario" -AsSecureString
    }

    $passwordPlano = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))

    try {
        $respuesta = Invoke-RestMethod -Method Post -Uri $urlToken -Body @{
            grant_type = "password"
            client_id  = $ClientIdFrontend
            scope      = "$scope openid profile"
            username   = $Usuario
            password   = $passwordPlano
        }
    } catch {
        $detalle = $_.ErrorDetails.Message
        Write-Host ""
        Write-Host "Entra ID rechazo la peticion:" -ForegroundColor Red
        Write-Host $detalle -ForegroundColor DarkGray
        Write-Host ""
        if ($detalle -match "AADSTS7000218") {
            Write-Host "AADSTS7000218: el registro no permite flujos de cliente publico." -ForegroundColor Yellow
            Write-Host "Pidele a tu companero: Entra ID -> App registrations -> Pedidos360-FRONTEND" -ForegroundColor Yellow
            Write-Host "  -> Authentication -> Advanced settings -> Allow public client flows = Yes" -ForegroundColor Yellow
        } elseif ($detalle -match "AADSTS50076|AADSTS50079") {
            Write-Host "La cuenta exige MFA. Usa el otro flujo:  .\obtener-token.ps1 -CodigoDispositivo" -ForegroundColor Yellow
        } elseif ($detalle -match "AADSTS50126") {
            Write-Host "Usuario o contrasena incorrectos." -ForegroundColor Yellow
        } elseif ($detalle -match "AADSTS65001") {
            Write-Host "Falta el consentimiento del scope $scope para esta aplicacion." -ForegroundColor Yellow
        }
        throw
    } finally {
        $passwordPlano = $null
        [GC]::Collect()
    }
}

$token = $respuesta.access_token

Show-Diagnostico -Jwt $token

Write-Host "=== Access token ===" -ForegroundColor Cyan
Write-Host $token
Write-Host ""

if ($GuardarEnVariable) {
    Set-Item -Path "env:$GuardarEnVariable" -Value $token
    Write-Host "Token guardado en `$env:$GuardarEnVariable (solo en esta sesion de PowerShell)." -ForegroundColor Green
    Write-Host ""
}

Set-Clipboard -Value $token
Write-Host "Tambien quedo copiado al portapapeles, listo para pegar en Postman." -ForegroundColor Green
Write-Host ""
