<#
.SINOPSIS
    Crea (o reutiliza) la instancia EC2, su Security Group y su par de llaves.

.DESCRIPCION
    Pensado para AWS Academy Learner Lab:
      - Usa la VPC por defecto (el lab no deja crear VPCs con libertad).
      - No crea roles IAM (el lab solo permite LabRole / LabInstanceProfile).
      - Abre 8080 al mundo porque las HTTP API de API Gateway salen desde IPs
        publicas que no se pueden acotar sin VPC Link.
      - Abre 22 SOLO a tu IP publica actual.

.EJEMPLO
    .\00-crear-ec2.ps1
#>
[CmdletBinding()]
param(
    [string]$Region = "us-east-1",
    [string]$NombreInstancia = "pedidos360-bff",
    [string]$NombreSg = "pedidos360-bff-sg",
    [string]$NombreLlave = "pedidos360-key",
    [string]$TipoInstancia = "t3.micro",
    [int]$PuertoBff = 8080,

    # Asigna y asocia una Elastic IP para que la direccion publica no cambie
    # entre sesiones del lab. Si la cuenta no lo permite, avisa y continua.
    [switch]$ConIpElastica
)

$ErrorActionPreference = "Stop"

function Invoke-Aws {
    param([string[]]$Argumentos, [switch]$PermitirFallo)

    # En PowerShell 5.1, redirigir 2>&1 sobre un ejecutable nativo envuelve cada
    # linea de stderr en un ErrorRecord. Con $ErrorActionPreference = 'Stop' eso
    # aborta el script aunque el AWS CLI haya terminado con codigo 0 y solo haya
    # escrito un aviso. Por eso se baja la preferencia solo alrededor de la
    # llamada y se decide el exito con $LASTEXITCODE, que es la unica senal fiable.
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

# ---------------------------------------------------------------------------
# 1. VPC por defecto
# ---------------------------------------------------------------------------

$vpcs = Invoke-Aws @("ec2", "describe-vpcs", "--filters", "Name=isDefault,Values=true")
if (-not $vpcs.Vpcs) { throw "No hay VPC por defecto en $Region." }
$vpcId = $vpcs.Vpcs[0].VpcId
Write-Host "[1/5] VPC por defecto: $vpcId" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 2. Security Group
# ---------------------------------------------------------------------------

$sgs = Invoke-Aws @("ec2", "describe-security-groups",
    "--filters", "Name=group-name,Values=$NombreSg", "Name=vpc-id,Values=$vpcId") -PermitirFallo

if ($sgs -and $sgs.SecurityGroups) {
    $sgId = $sgs.SecurityGroups[0].GroupId
    Write-Host "[2/5] Security Group existente: $sgId" -ForegroundColor Yellow
} else {
    $sg = Invoke-Aws @("ec2", "create-security-group",
        "--group-name", $NombreSg,
        "--description", "Pedidos360 - solo BFF expuesto",
        "--vpc-id", $vpcId)
    $sgId = $sg.GroupId
    Write-Host "[2/5] Security Group creado: $sgId" -ForegroundColor Green
}

# Puerto del BFF abierto al mundo: API Gateway HTTP API no tiene rango fijo.
Invoke-Aws @("ec2", "authorize-security-group-ingress",
    "--group-id", $sgId,
    "--protocol", "tcp", "--port", "$PuertoBff", "--cidr", "0.0.0.0/0") -PermitirFallo | Out-Null

# SSH restringido a tu IP publica actual.
try {
    $miIp = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim()
    Invoke-Aws @("ec2", "authorize-security-group-ingress",
        "--group-id", $sgId,
        "--protocol", "tcp", "--port", "22", "--cidr", "$miIp/32") -PermitirFallo | Out-Null
    Write-Host "      SSH permitido solo desde $miIp/32" -ForegroundColor Green
} catch {
    Write-Host "      No se pudo detectar tu IP publica. Abre el 22 manualmente." -ForegroundColor Yellow
}

Write-Host "      NOTA: 8081 y 8082 NO se abren. Los microservicios son privados." -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# 3. Par de llaves
# ---------------------------------------------------------------------------

$rutaPem = Join-Path $PSScriptRoot "$NombreLlave.pem"
$llaves = Invoke-Aws @("ec2", "describe-key-pairs", "--key-names", $NombreLlave) -PermitirFallo

if ($llaves -and $llaves.KeyPairs) {
    Write-Host "[3/5] Par de llaves '$NombreLlave' ya existe en AWS." -ForegroundColor Yellow
    if (-not (Test-Path $rutaPem)) {
        Write-Host "      OJO: no esta el .pem local. Si lo perdiste, borra la llave en AWS y vuelve a correr:" -ForegroundColor Yellow
        Write-Host "      aws ec2 delete-key-pair --key-name $NombreLlave --region $Region" -ForegroundColor DarkGray
    }
} else {
    $material = & aws ec2 create-key-pair --key-name $NombreLlave --query "KeyMaterial" --output text --region $Region
    if ($LASTEXITCODE -ne 0) { throw "No se pudo crear el par de llaves." }
    Set-Content -Path $rutaPem -Value $material -Encoding ascii

    # Windows exige permisos restrictivos o SSH rechaza la llave.
    icacls $rutaPem /inheritance:r | Out-Null
    icacls $rutaPem /grant:r "$($env:USERNAME):(R)" | Out-Null

    Write-Host "[3/5] Llave creada y guardada en $rutaPem" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 4. Instancia
# ---------------------------------------------------------------------------

$existentes = Invoke-Aws @("ec2", "describe-instances",
    "--filters", "Name=tag:Name,Values=$NombreInstancia",
                 "Name=instance-state-name,Values=pending,running,stopping,stopped")

$instancia = $null
if ($existentes.Reservations.Count -gt 0) {
    $instancia = $existentes.Reservations[0].Instances[0]
    Write-Host "[4/5] Instancia existente: $($instancia.InstanceId) (estado: $($instancia.State.Name))" -ForegroundColor Yellow

    if ($instancia.State.Name -eq "stopped") {
        Write-Host "      Arrancandola..." -ForegroundColor Cyan
        Invoke-Aws @("ec2", "start-instances", "--instance-ids", $instancia.InstanceId) | Out-Null
        & aws ec2 wait instance-running --instance-ids $instancia.InstanceId --region $Region
    }
} else {
    # AMI de Amazon Linux 2023 mas reciente, resuelta via SSM (no se hardcodea:
    # el id cambia por region y con cada release).
    $ami = & aws ssm get-parameters `
        --names "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64" `
        --query "Parameters[0].Value" --output text --region $Region
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ami)) {
        throw "No se pudo resolver la AMI de Amazon Linux 2023."
    }
    Write-Host "      AMI: $ami" -ForegroundColor DarkGray

    $rutaUserData = Join-Path $PSScriptRoot "ec2-user-data.sh"
    if (-not (Test-Path $rutaUserData)) { throw "Falta $rutaUserData" }
    $uriUserData = "file://" + ($rutaUserData -replace '\\', '/')

    $lanzada = Invoke-Aws @("ec2", "run-instances",
        "--image-id", $ami,
        "--instance-type", $TipoInstancia,
        "--key-name", $NombreLlave,
        "--security-group-ids", $sgId,
        "--user-data", $uriUserData,
        "--tag-specifications", "ResourceType=instance,Tags=[{Key=Name,Value=$NombreInstancia}]",
        "--metadata-options", "HttpTokens=required,HttpEndpoint=enabled")

    $instanciaId = $lanzada.Instances[0].InstanceId
    Write-Host "[4/5] Instancia lanzada: $instanciaId. Esperando a que este running..." -ForegroundColor Green
    & aws ec2 wait instance-running --instance-ids $instanciaId --region $Region

    $descripcion = Invoke-Aws @("ec2", "describe-instances", "--instance-ids", $instanciaId)
    $instancia = $descripcion.Reservations[0].Instances[0]
}

$instanciaId = $instancia.InstanceId

# ---------------------------------------------------------------------------
# 4b. Elastic IP (opcional pero muy recomendable en el Learner Lab)
# ---------------------------------------------------------------------------
#
# Sin IP elastica, la instancia recibe una IP publica distinta cada vez que se
# detiene y arranca, o sea en cada sesion del lab, y hay que re-apuntar las 22
# integraciones del API Gateway. Con una IP elastica asociada, la direccion
# sobrevive a los reinicios y el API Gateway no se toca nunca mas.

if ($ConIpElastica) {
    $etiqueta = "$NombreInstancia-eip"

    $existentes = Invoke-Aws @("ec2", "describe-addresses",
        "--filters", "Name=tag:Name,Values=$etiqueta") -PermitirFallo

    if ($existentes -and $existentes.Addresses.Count -gt 0) {
        $eip = $existentes.Addresses[0]
        Write-Host "[4b] Elastic IP existente reutilizada: $($eip.PublicIp)" -ForegroundColor Yellow
        $allocationId = $eip.AllocationId
        $ipElastica = $eip.PublicIp
    } else {
        $nueva = Invoke-Aws @("ec2", "allocate-address",
            "--domain", "vpc",
            "--tag-specifications", "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$etiqueta}]") -PermitirFallo

        if (-not $nueva) {
            Write-Host "[4b] Esta cuenta no permite asignar Elastic IP. Se continua con la IP dinamica." -ForegroundColor Yellow
            Write-Host "     Tendras que correr 03-actualizar-destino-bff.ps1 al inicio de cada sesion." -ForegroundColor Yellow
            $allocationId = $null
        } else {
            $allocationId = $nueva.AllocationId
            $ipElastica = $nueva.PublicIp
            Write-Host "[4b] Elastic IP asignada: $ipElastica" -ForegroundColor Green
        }
    }

    if ($allocationId) {
        Invoke-Aws @("ec2", "associate-address",
            "--instance-id", $instanciaId,
            "--allocation-id", $allocationId) | Out-Null
        Write-Host "     Asociada a $instanciaId. La IP ya no cambia entre sesiones." -ForegroundColor Green
    }
}

$descripcion = Invoke-Aws @("ec2", "describe-instances", "--instance-ids", $instanciaId)
$ipPublica = $descripcion.Reservations[0].Instances[0].PublicIpAddress

# ---------------------------------------------------------------------------
# 5. Resumen
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "[5/5] Instancia lista" -ForegroundColor Green
Write-Host "  InstanceId : $instanciaId"
Write-Host "  IP publica : $ipPublica"
Write-Host "  URL del BFF: http://${ipPublica}:$PuertoBff"
Write-Host ""
Write-Host "Siguientes pasos:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Copiar los JAR (el user-data tarda ~2 min en instalar Java):"
Write-Host "     scp -i `"$rutaPem`" ms-pedidos360-catalog.jar ms-pedidos360-orders.jar bff-pedidos360.jar ec2-user@${ipPublica}:/tmp/" -ForegroundColor DarkGray
Write-Host "     ssh -i `"$rutaPem`" ec2-user@$ipPublica 'sudo mv /tmp/*.jar /opt/pedidos360/bin/ && sudo chown pedidos360:pedidos360 /opt/pedidos360/bin/*.jar'" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2. Arrancar los servicios:"
Write-Host "     ssh -i `"$rutaPem`" ec2-user@$ipPublica 'sudo systemctl enable --now ms-catalog ms-orders bff'" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  3. Apuntar el API Gateway a esta instancia:"
Write-Host "     .\02-desplegar-api-gateway.ps1 -DestinoBff `"http://${ipPublica}:$PuertoBff`"" -ForegroundColor DarkGray
Write-Host ""
if ($ConIpElastica -and $allocationId) {
    Write-Host "  Con la Elastic IP asociada, esta direccion sobrevive a los reinicios:" -ForegroundColor Green
    Write-Host "  en las proximas sesiones del lab solo tienes que arrancar la instancia," -ForegroundColor Green
    Write-Host "  sin tocar el API Gateway." -ForegroundColor Green
    Write-Host ""
    Write-Host "     aws ec2 start-instances --instance-ids $instanciaId --region $Region" -ForegroundColor DarkGray
} else {
    Write-Host "  Sin Elastic IP, la direccion cambia en cada sesion del lab."
    Write-Host "  Despues de arrancar la instancia hay que re-apuntar el API Gateway:"
    Write-Host "     .\03-actualizar-destino-bff.ps1 -DesdeInstancia $instanciaId" -ForegroundColor DarkGray
}
Write-Host ""
