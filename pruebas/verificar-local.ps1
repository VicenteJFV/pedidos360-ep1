<#
.SINOPSIS
    Levanta los dos microservicios y verifica el flujo de negocio completo
    de punta a punta, sin AWS, sin Entra ID y sin el BFF.

.DESCRIPCION
    Arranca catalogo (8082) y pedidos (8081), ejecuta 26 comprobaciones sobre
    la maquina de estados y el control de stock, imprime un resumen y apaga
    todo al terminar.

    Es la verificacion que conviene correr antes de tocar AWS: si algo falla
    aca, depurarlo en tu maquina es mucho mas rapido que por SSH en una EC2.

.EJEMPLO
    .\verificar-local.ps1
#>
[CmdletBinding()]
param(
    [string]$RaizProyecto = (Split-Path $PSScriptRoot -Parent),
    [int]$SegundosEspera = 60
)

$ErrorActionPreference = "Stop"
$script:ok = 0
$script:fallos = @()

function Invoke-Api {
    param([string]$Metodo, [string]$Url, $Cuerpo)

    $params = @{ Method = $Metodo; Uri = $Url; UseBasicParsing = $true; TimeoutSec = 20 }
    if ($null -ne $Cuerpo) {
        $params.Body = ($Cuerpo | ConvertTo-Json -Depth 6)
        $params.ContentType = "application/json; charset=utf-8"
    }

    try {
        $r = Invoke-WebRequest @params
        $json = $null
        if ($r.Content) {
            try { $json = $r.Content | ConvertFrom-Json } catch { }
        }
        return @{ Status = [int]$r.StatusCode; Json = $json }
    } catch {
        $resp = $_.Exception.Response
        if (-not $resp) {
            return @{ Status = 0; Json = $null }
        }
        $status = [int]$resp.StatusCode
        $json = $null
        try {
            $lector = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $texto = $lector.ReadToEnd()
            if ($texto) { $json = $texto | ConvertFrom-Json }
        } catch { }
        return @{ Status = $status; Json = $json }
    }
}

function Comprobar {
    param([string]$Nombre, [bool]$Condicion, [string]$Detalle = "")
    if ($Condicion) {
        Write-Host ("  [OK]    " + $Nombre) -ForegroundColor Green
        $script:ok++
    } else {
        Write-Host ("  [FALLA] " + $Nombre) -ForegroundColor Red
        if ($Detalle) { Write-Host ("          " + $Detalle) -ForegroundColor DarkGray }
        $script:fallos += $Nombre
    }
}

$jarCatalogo = Join-Path $RaizProyecto "ms-pedidos360-catalog\target\ms-pedidos360-catalog.jar"
$jarPedidos  = Join-Path $RaizProyecto "ms-pedidos360-orders\target\ms-pedidos360-orders.jar"

foreach ($jar in @($jarCatalogo, $jarPedidos)) {
    if (-not (Test-Path $jar)) {
        throw "Falta $jar . Compila primero con: mvn clean package"
    }
}

$carpetaLogs = Join-Path $RaizProyecto "logs"
if (-not (Test-Path $carpetaLogs)) { New-Item -ItemType Directory -Path $carpetaLogs | Out-Null }

$procesos = @()
$urlCat = "http://127.0.0.1:8082"
$urlPed = "http://127.0.0.1:8081"

try {
    Write-Host ""
    Write-Host "=== Arrancando microservicios ===" -ForegroundColor Cyan

    $procesos += Start-Process -FilePath "java" -ArgumentList "-jar `"$jarCatalogo`"" -RedirectStandardOutput "$carpetaLogs\catalog.log" -RedirectStandardError "$carpetaLogs\catalog.err" -WindowStyle Hidden -PassThru
    $procesos += Start-Process -FilePath "java" -ArgumentList "-jar `"$jarPedidos`"" -RedirectStandardOutput "$carpetaLogs\orders.log" -RedirectStandardError "$carpetaLogs\orders.err" -WindowStyle Hidden -PassThru

    $arriba = $false
    $esperados = 0
    for ($i = 1; $i -le $SegundosEspera; $i++) {
        Start-Sleep -Seconds 1
        $esperados = $i
        $c = Invoke-Api GET "$urlCat/actuator/health"
        $o = Invoke-Api GET "$urlPed/actuator/health"
        if ($c.Status -eq 200 -and $o.Status -eq 200) { $arriba = $true; break }
    }

    if (-not $arriba) {
        Write-Host "Los servicios no respondieron en $SegundosEspera segundos." -ForegroundColor Red
        Write-Host "--- catalog.log ---" -ForegroundColor DarkGray
        Get-Content "$carpetaLogs\catalog.log" -Tail 25 -ErrorAction SilentlyContinue
        Write-Host "--- orders.log ---" -ForegroundColor DarkGray
        Get-Content "$carpetaLogs\orders.log" -Tail 25 -ErrorAction SilentlyContinue
        throw "Arranque fallido"
    }

    Write-Host "  catalogo 8082 y pedidos 8081 respondiendo (tras $esperados s)" -ForegroundColor Green

    Write-Host ""
    Write-Host "=== Catalogo ===" -ForegroundColor Cyan

    $lista = Invoke-Api GET "$urlCat/api/catalog"
    Comprobar "GET /api/catalog responde 200" ($lista.Status -eq 200) "status=$($lista.Status)"
    Comprobar "Los datos de demostracion se cargaron" ($lista.Json.Count -ge 7) "productos=$($lista.Json.Count)"

    $producto = $lista.Json | Where-Object { $_.sku -eq "SKU-001" } | Select-Object -First 1
    $idProducto = $producto.id
    $stockInicial = [int]$producto.stock
    $precio = [decimal]$producto.precio
    Write-Host "  (usando $($producto.sku): stock $stockInicial, precio $precio)" -ForegroundColor DarkGray

    $dup = Invoke-Api POST "$urlCat/api/catalog" @{ sku = "SKU-001"; nombre = "Duplicado"; precio = 1000; stock = 1; categoria = "TEST" }
    Comprobar "SKU duplicado se rechaza con 409" ($dup.Status -eq 409) "status=$($dup.Status)"

    $malo = Invoke-Api POST "$urlCat/api/catalog" @{ sku = ""; nombre = ""; precio = -5; stock = -1 }
    Comprobar "Validacion de entrada devuelve 400" ($malo.Status -eq 400) "status=$($malo.Status)"

    $inexistente = Invoke-Api GET "$urlCat/api/catalog/999999"
    Comprobar "Producto inexistente devuelve 404" ($inexistente.Status -eq 404) "status=$($inexistente.Status)"

    Write-Host ""
    Write-Host "=== Maquina de estados del pedido ===" -ForegroundColor Cyan

    $nuevo = Invoke-Api POST "$urlPed/api/orders" @{
        clienteEmail     = "cliente@duoc.cl"
        clienteNombre    = "Cliente de prueba"
        direccionEntrega = "Av. Siempre Viva 742"
        items            = @(@{ productoId = $idProducto; cantidad = 2 })
    }
    Comprobar "POST /api/orders devuelve 201" ($nuevo.Status -eq 201) "status=$($nuevo.Status)"
    Comprobar "El pedido nace en CREADO" ($nuevo.Json.estado -eq "CREADO") "estado=$($nuevo.Json.estado)"
    Comprobar "El total se calcula bien" ([decimal]$nuevo.Json.total -eq ($precio * 2)) "total=$($nuevo.Json.total) esperado=$($precio * 2)"

    $idPedido = $nuevo.Json.id

    $trasCrear = Invoke-Api GET "$urlCat/api/catalog/$idProducto"
    Comprobar "Crear el pedido NO descuenta stock" ([int]$trasCrear.Json.stock -eq $stockInicial) "stock=$($trasCrear.Json.stock) esperado=$stockInicial"

    $temprano = Invoke-Api PUT "$urlPed/api/orders/$idPedido/dispatch"
    Comprobar "No se puede despachar sin aceptar (409)" ($temprano.Status -eq 409) "status=$($temprano.Status)"

    $aceptado = Invoke-Api PUT "$urlPed/api/orders/$idPedido/accept"
    Comprobar "Aceptar pasa a ACEPTADO" ($aceptado.Json.estado -eq "ACEPTADO") "estado=$($aceptado.Json.estado)"

    $trasAceptar = Invoke-Api GET "$urlCat/api/catalog/$idProducto"
    Comprobar "Aceptar SI descuenta stock en el catalogo" ([int]$trasAceptar.Json.stock -eq ($stockInicial - 2)) "stock=$($trasAceptar.Json.stock) esperado=$($stockInicial - 2)"

    $prep = Invoke-Api PUT "$urlPed/api/orders/$idPedido/prepare"
    Comprobar "Preparar pasa a EN_PREPARACION" ($prep.Json.estado -eq "EN_PREPARACION") "estado=$($prep.Json.estado)"

    $desp = Invoke-Api PUT "$urlPed/api/orders/$idPedido/dispatch"
    Comprobar "Despachar pasa a DESPACHADO" ($desp.Json.estado -eq "DESPACHADO") "estado=$($desp.Json.estado)"

    $ent = Invoke-Api PUT "$urlPed/api/orders/$idPedido/deliver"
    Comprobar "Entregar pasa a ENTREGADO" ($ent.Json.estado -eq "ENTREGADO") "estado=$($ent.Json.estado)"
    Comprobar "ENTREGADO no admite mas transiciones" ($ent.Json.transicionesPermitidas.Count -eq 0) "transiciones=$($ent.Json.transicionesPermitidas -join ',')"

    $tarde = Invoke-Api PUT "$urlPed/api/orders/$idPedido/cancel" @{ motivo = "muy tarde" }
    Comprobar "Cancelar un pedido entregado da 409" ($tarde.Status -eq 409) "status=$($tarde.Status)"

    Write-Host ""
    Write-Host "=== Reposicion de stock y limites ===" -ForegroundColor Cyan

    $stockAntes = [int](Invoke-Api GET "$urlCat/api/catalog/$idProducto").Json.stock

    $p2 = Invoke-Api POST "$urlPed/api/orders" @{
        clienteEmail = "cliente@duoc.cl"
        items        = @(@{ productoId = $idProducto; cantidad = 3 })
    }
    Invoke-Api PUT "$urlPed/api/orders/$($p2.Json.id)/accept" | Out-Null
    $stockReservado = [int](Invoke-Api GET "$urlCat/api/catalog/$idProducto").Json.stock

    $cancelado = Invoke-Api PUT "$urlPed/api/orders/$($p2.Json.id)/cancel" @{ motivo = "el cliente se arrepintio" }
    $stockRepuesto = [int](Invoke-Api GET "$urlCat/api/catalog/$idProducto").Json.stock

    Comprobar "Cancelar un pedido aceptado lo pasa a CANCELADO" ($cancelado.Json.estado -eq "CANCELADO") "estado=$($cancelado.Json.estado)"
    Comprobar "Aceptar reservo el stock" ($stockReservado -eq ($stockAntes - 3)) "reservado=$stockReservado esperado=$($stockAntes - 3)"
    Comprobar "Cancelar repone el stock" ($stockRepuesto -eq $stockAntes) "repuesto=$stockRepuesto esperado=$stockAntes"

    # Cantidad dentro del tope por linea (999) pero muy por encima del stock:
    # asi el rechazo viene de la regla de negocio y no de la validacion de entrada.
    $exceso = Invoke-Api POST "$urlPed/api/orders" @{
        clienteEmail = "cliente@duoc.cl"
        items        = @(@{ productoId = $idProducto; cantidad = 500 })
    }
    Comprobar "Stock insuficiente devuelve 409" ($exceso.Status -eq 409) "status=$($exceso.Status)"
    Comprobar "El 409 explica que producto falto" ($exceso.Json.detalles -and ($exceso.Json.detalles -join ' ') -match 'SKU-001') "detalles=$($exceso.Json.detalles -join ' | ')"

    # Por encima del tope por linea: esto SI debe ser 400, no 409.
    $topeLinea = Invoke-Api POST "$urlPed/api/orders" @{
        clienteEmail = "cliente@duoc.cl"
        items        = @(@{ productoId = $idProducto; cantidad = 99999 })
    }
    Comprobar "Cantidad sobre el tope por linea devuelve 400" ($topeLinea.Status -eq 400) "status=$($topeLinea.Status)"

    $enumMalo = Invoke-Api GET "$urlPed/api/orders?estado=INVENTADO"
    Comprobar "Estado invalido en el filtro devuelve 400" ($enumMalo.Status -eq 400) "status=$($enumMalo.Status)"

    $filtrado = Invoke-Api GET "$urlPed/api/orders?clienteEmail=cliente@duoc.cl"
    Comprobar "El filtro por cliente funciona" ($filtrado.Status -eq 200 -and $filtrado.Json.Count -ge 2) "status=$($filtrado.Status) pedidos=$($filtrado.Json.Count)"

    Write-Host ""
    Write-Host "=== Aislamiento de red ===" -ForegroundColor Cyan

    $ipLan = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
              Select-Object -First 1).IPAddress

    if ($ipLan) {
        $externo = Invoke-Api GET "http://${ipLan}:8081/api/orders"
        Comprobar "Los microservicios NO son accesibles fuera de loopback" ($externo.Status -eq 0) "probado en ${ipLan}:8081 status=$($externo.Status)"
    } else {
        Write-Host "  (sin IP de red detectada, se omite)" -ForegroundColor DarkGray
    }

} finally {
    Write-Host ""
    Write-Host "=== Apagando microservicios ===" -ForegroundColor Cyan
    foreach ($p in $procesos) {
        if ($p -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Write-Host "  detenido PID $($p.Id)" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
if ($script:fallos.Count -eq 0) {
    Write-Host " TODO CORRECTO - $($script:ok) comprobaciones" -ForegroundColor Green
} else {
    Write-Host " $($script:ok) correctas, $($script:fallos.Count) fallidas" -ForegroundColor Red
    $script:fallos | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host " Logs en: $carpetaLogs" -ForegroundColor DarkGray
}
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""
