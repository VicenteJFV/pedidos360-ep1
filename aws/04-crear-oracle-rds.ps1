<#
.SINOPSIS
    Crea una base de datos Oracle en Amazon RDS y deja los microservicios
    apuntando a ella.

.DESCRIPCION
    Alternativa a Oracle Autonomous Database cuando no se puede crear una
    cuenta en Oracle Cloud. Es Oracle de verdad: mismo motor, mismo driver
    ojdbc11, mismo dialecto de Hibernate y mismo SQL. Lo unico que cambia es
    quien lo aloja.

    Ventajas sobre la ADB en este contexto:
      - No requiere cuenta de Oracle Cloud ni tarjeta de credito.
      - No usa wallet: conexion TCP directa, sin TNS_ADMIN ni archivos extra.
      - Queda dentro de la misma VPC que la EC2, sin exponerse a Internet.

    COSTO: Oracle SE2 con licencia incluida en db.t3.small cuesta del orden de
    US$0,10-0,20 por hora mas el almacenamiento. Con el presupuesto del Learner
    Lab alcanza de sobra para la evaluacion, pero conviene detener la instancia
    cuando no se use:

        aws rds stop-db-instance --db-instance-identifier pedidos360-oracle

    La contrasena se pide por consola y nunca se escribe en disco local ni
    queda en el historial de comandos.

.EJEMPLO
    .\04-crear-oracle-rds.ps1

.EJEMPLO
    # Crea la base y ademas deja la EC2 configurada y reiniciada
    .\04-crear-oracle-rds.ps1 -ConfigurarEc2 -IpEc2 32.194.66.142
#>
[CmdletBinding()]
param(
    [string]$Region = "us-east-1",
    [string]$Identificador = "pedidos360-oracle",
    [string]$NombreBd = "PEDIDOS",
    [string]$Usuario = "admin",
    [string]$Clase = "db.t3.small",
    [int]$Almacenamiento = 20,

    # Security Group de la EC2, el unico origen autorizado al puerto 1521.
    [string]$SgEc2 = "pedidos360-bff-sg",
    [string]$SgOracle = "pedidos360-oracle-sg",

    # Tras crear la base, configura /opt/pedidos360/entorno y reinicia los
    # microservicios con el perfil oracle.
    [switch]$ConfigurarEc2,

    # Opcional. Si se omite, se resuelve desde AWS buscando la instancia por su
    # etiqueta Name: es menos propenso a errores que escribir la IP a mano.
    [string]$IpEc2,
    [string]$NombreInstancia = "pedidos360-bff",
    [string]$RutaLlave = (Join-Path $PSScriptRoot "pedidos360-key.pem")
)

$ErrorActionPreference = "Stop"

function Invoke-Aws {
    param([string[]]$Argumentos, [switch]$PermitirFallo)
    $previo = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $salida = & aws @Argumentos --region $Region --output json 2>&1
        $codigo = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previo
    }
    if ($codigo -ne 0) {
        if ($PermitirFallo) { return $null }
        throw "Fallo el comando: aws $($Argumentos -join ' ')`n$($salida | Out-String)"
    }
    $texto = ($salida | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($texto)) { return $null }
    return ($texto | ConvertFrom-Json)
}

Write-Host ""
Write-Host "=== Oracle en Amazon RDS ===" -ForegroundColor Cyan
Write-Host "  Identificador : $Identificador"
Write-Host "  Motor         : oracle-se2 (licencia incluida)"
Write-Host "  Clase         : $Clase"
Write-Host "  Base de datos : $NombreBd"
Write-Host ""
Write-Host "  Costo aproximado: US`$0,10-0,20 por hora mientras este encendida." -ForegroundColor Yellow
Write-Host "  Detenla cuando no la uses:" -ForegroundColor Yellow
Write-Host "    aws rds stop-db-instance --db-instance-identifier $Identificador --region $Region" -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Reutilizar si ya existe
# ---------------------------------------------------------------------------

$existente = Invoke-Aws @("rds", "describe-db-instances", "--db-instance-identifier", $Identificador) -PermitirFallo

if ($existente) {
    $bd = $existente.DBInstances[0]
    Write-Host "[1/5] Ya existe (estado: $($bd.DBInstanceStatus))." -ForegroundColor Yellow
    if ($bd.DBInstanceStatus -eq "stopped") {
        Write-Host "      Arrancandola..." -ForegroundColor Cyan
        Invoke-Aws @("rds", "start-db-instance", "--db-instance-identifier", $Identificador) | Out-Null
    }
    $clave = $null
} else {

    # -----------------------------------------------------------------------
    # 2. Security Group: solo la EC2 puede llegar al 1521
    # -----------------------------------------------------------------------

    $vpcs = Invoke-Aws @("ec2", "describe-vpcs", "--filters", "Name=isDefault,Values=true")
    $vpcId = $vpcs.Vpcs[0].VpcId

    $sgEc2Info = Invoke-Aws @("ec2", "describe-security-groups",
        "--filters", "Name=group-name,Values=$SgEc2", "Name=vpc-id,Values=$vpcId")
    if (-not $sgEc2Info.SecurityGroups) {
        throw "No se encontro el Security Group '$SgEc2'. Ejecuta primero 00-crear-ec2.ps1."
    }
    $idSgEc2 = $sgEc2Info.SecurityGroups[0].GroupId

    $sgOraInfo = Invoke-Aws @("ec2", "describe-security-groups",
        "--filters", "Name=group-name,Values=$SgOracle", "Name=vpc-id,Values=$vpcId") -PermitirFallo

    if ($sgOraInfo -and $sgOraInfo.SecurityGroups) {
        $idSgOracle = $sgOraInfo.SecurityGroups[0].GroupId
        Write-Host "[1/5] Security Group de Oracle reutilizado: $idSgOracle" -ForegroundColor Yellow
    } else {
        $sg = Invoke-Aws @("ec2", "create-security-group",
            "--group-name", $SgOracle,
            "--description", "Pedidos360 - acceso a Oracle solo desde la EC2",
            "--vpc-id", $vpcId)
        $idSgOracle = $sg.GroupId
        Write-Host "[1/5] Security Group de Oracle creado: $idSgOracle" -ForegroundColor Green
    }

    # El origen es el Security Group de la EC2, no un rango de IP: si la
    # instancia cambia de direccion, la regla sigue siendo valida.
    Invoke-Aws @("ec2", "authorize-security-group-ingress",
        "--group-id", $idSgOracle,
        "--protocol", "tcp", "--port", "1521",
        "--source-group", $idSgEc2) -PermitirFallo | Out-Null
    Write-Host "      Puerto 1521 abierto solo para $SgEc2 ($idSgEc2)" -ForegroundColor Green

    # -----------------------------------------------------------------------
    # 3. Contrasena: se pide aqui y no se guarda en ningun archivo
    # -----------------------------------------------------------------------

    Write-Host ""
    Write-Host "Define la contrasena del usuario maestro '$Usuario'." -ForegroundColor Cyan
    Write-Host "Requisitos de Oracle RDS: 8 a 30 caracteres, sin comillas, / ni @." -ForegroundColor DarkGray
    $segura = Read-Host "Contrasena" -AsSecureString
    $confirmar = Read-Host "Confirmala" -AsSecureString

    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura))
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmar))
    if ($p1 -ne $p2) { throw "Las contrasenas no coinciden." }
    if ($p1.Length -lt 8 -or $p1.Length -gt 30) { throw "La contrasena debe tener entre 8 y 30 caracteres." }
    if ($p1 -match '[''"/@]') { throw "La contrasena no puede contener comillas, / ni @." }
    $clave = $p1
    $p2 = $null

    # -----------------------------------------------------------------------
    # 4. Crear la instancia
    # -----------------------------------------------------------------------

    Write-Host ""
    Write-Host "[2/5] Creando la instancia. Oracle tarda entre 15 y 25 minutos." -ForegroundColor Cyan

    Invoke-Aws @("rds", "create-db-instance",
        "--db-instance-identifier", $Identificador,
        "--db-instance-class", $Clase,
        "--engine", "oracle-se2",
        "--engine-version", "19.0.0.0.ru-2026-07.spb-1.r1",
        "--license-model", "license-included",
        "--allocated-storage", "$Almacenamiento",
        "--storage-type", "gp3",
        "--db-name", $NombreBd,
        "--master-username", $Usuario,
        "--master-user-password", $clave,
        "--vpc-security-group-ids", $idSgOracle,
        "--no-publicly-accessible",
        "--backup-retention-period", "0",
        "--no-multi-az",
        "--no-auto-minor-version-upgrade",
        "--character-set-name", "AL32UTF8") | Out-Null
}

# ---------------------------------------------------------------------------
# 5. Esperar y mostrar la conexion
# ---------------------------------------------------------------------------

Write-Host "[3/5] Esperando a que quede disponible..." -ForegroundColor Cyan
& aws rds wait db-instance-available --db-instance-identifier $Identificador --region $Region
if ($LASTEXITCODE -ne 0) { throw "La instancia no llego a estado disponible." }

$bd = (Invoke-Aws @("rds", "describe-db-instances", "--db-instance-identifier", $Identificador)).DBInstances[0]
$host_ = $bd.Endpoint.Address
$puerto = $bd.Endpoint.Port
$sid = $bd.DBName

$jdbc = "jdbc:oracle:thin:@//${host_}:${puerto}/${sid}"

Write-Host "[4/5] Disponible." -ForegroundColor Green
Write-Host "      Endpoint : ${host_}:${puerto}"
Write-Host "      SID      : $sid"
Write-Host "      JDBC URL : $jdbc"
Write-Host ""
Write-Host "      No es accesible desde Internet: solo responde a la EC2." -ForegroundColor Green

# ---------------------------------------------------------------------------
# 6. Dejar la EC2 configurada
# ---------------------------------------------------------------------------

if ($ConfigurarEc2) {
    if (-not (Test-Path $RutaLlave)) { throw "No se encontro la llave $RutaLlave" }

    # La IP real se consulta siempre a AWS. Si el usuario paso una, se compara:
    # una IP mal escrita solo se manifiesta como un timeout de SSH varios pasos
    # despues, y eso es dificil de diagnosticar.
    $desc = Invoke-Aws @("ec2", "describe-instances",
        "--filters", "Name=tag:Name,Values=$NombreInstancia",
                     "Name=instance-state-name,Values=running")

    if (-not $desc.Reservations -or $desc.Reservations.Count -eq 0) {
        throw "No hay ninguna instancia '$NombreInstancia' en estado running. Arrancala primero."
    }
    $ipReal = $desc.Reservations[0].Instances[0].PublicIpAddress

    if (-not $IpEc2) {
        $IpEc2 = $ipReal
        Write-Host "      IP resuelta desde AWS: $IpEc2" -ForegroundColor DarkGray
    } elseif ($IpEc2 -ne $ipReal) {
        Write-Host ""
        Write-Host "      La IP indicada ($IpEc2) no coincide con la de la instancia ($ipReal)." -ForegroundColor Yellow
        Write-Host "      Se usara la real: $ipReal" -ForegroundColor Yellow
        $IpEc2 = $ipReal
    }

    # Si la instancia ya existia, el script no conoce la contrasena: se pide
    # aqui. Nunca se guarda en disco local ni queda en el historial.
    if (-not $clave) {
        Write-Host ""
        Write-Host "La base ya existia, asi que necesito la contrasena de '$Usuario'" -ForegroundColor Cyan
        Write-Host "para escribirla en la EC2. Es la que definiste al crearla." -ForegroundColor DarkGray
        $segura = Read-Host "Contrasena" -AsSecureString
        $clave = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura))
        if ([string]::IsNullOrWhiteSpace($clave)) { throw "Contrasena vacia." }
    }

    Write-Host "[5/5] Configurando la EC2 y reiniciando los microservicios..." -ForegroundColor Cyan

    # El archivo de entorno se reescribe por SSH. La contrasena viaja por el
    # tunel cifrado y queda en la instancia con permisos 600, nunca en disco local.
    #
    # La plantilla va en comillas simples para que PowerShell NO interprete
    # nada: dentro hay sintaxis de bash con $ y $(...) que, en una cadena
    # interpolada, PowerShell intentaria ejecutar en la maquina local. Los
    # valores se inyectan despues con Replace, que no reinterpreta nada.
    $plantilla = @'
set -e
sudo tee /opt/pedidos360/entorno > /dev/null <<'ENTORNO'
SPRING_PROFILE=oracle
ORACLE_JDBC_URL=__JDBC__
ORACLE_USER=__USUARIO__
ORACLE_PASSWORD=__CLAVE__
ENTORNO
sudo chmod 600 /opt/pedidos360/entorno
sudo chown pedidos360:pedidos360 /opt/pedidos360/entorno
echo "Reiniciando el catalogo..."
sudo systemctl restart ms-catalog
sleep 35
echo "Reiniciando pedidos..."
sudo systemctl restart ms-orders
sleep 25
echo ""
echo "Estado de los servicios:"
systemctl is-active ms-catalog ms-orders bff
echo ""
echo "Productos en el catalogo:"
curl -s http://127.0.0.1:8082/api/catalog | head -c 300
echo ""
'@

    $remoto = $plantilla.
        Replace('__JDBC__',    $jdbc).
        Replace('__USUARIO__', $Usuario).
        Replace('__CLAVE__',   $clave)

    $remoto | & ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 `
        -i $RutaLlave "ec2-user@$IpEc2" "bash -s"

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "La configuracion remota fallo. Revisa los logs:" -ForegroundColor Red
        Write-Host "  ssh -i `"$RutaLlave`" ec2-user@$IpEc2 'sudo tail -40 /opt/pedidos360/logs/catalog.log'" -ForegroundColor DarkGray
        throw "Fallo la configuracion en la EC2."
    }

    Write-Host ""
    Write-Host "      Listo. Verifica que los datos persistan:" -ForegroundColor Green
    Write-Host "        ssh -i `"$RutaLlave`" ec2-user@$IpEc2 'curl -s localhost:8082/api/catalog'" -ForegroundColor DarkGray
} else {
    Write-Host "[5/5] Para configurar la EC2, vuelve a ejecutar con:" -ForegroundColor Cyan
    Write-Host "        .\04-crear-oracle-rds.ps1 -ConfigurarEc2 -IpEc2 <IP>" -ForegroundColor DarkGray
}

$clave = $null
[GC]::Collect()
Write-Host ""
