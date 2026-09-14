# Pedidos360 — AWS, API Gateway y Microservicios (EP1 DSY1107)

Mi parte de la evaluación: los dos microservicios de negocio, la persistencia en Oracle y toda la infraestructura AWS.

```
pedidos360/
├── ms-pedidos360-orders/     Microservicio principal (8081) — pedidos y máquina de estados
├── ms-pedidos360-catalog/    Microservicio de catálogo (8082) — productos y stock
├── aws/                      Scripts de infraestructura y API Gateway
└── pruebas/                  Verificación local, token de Entra ID y colección Postman
```

## Contrato de integración

El BFF y el frontend Angular viven en repositorios aparte. El punto de contacto entre las tres piezas es este:

| Componente | Dirección | Expuesto |
| :--- | :--- | :--- |
| AWS API Gateway | `https://xpglku1pj5.execute-api.us-east-1.amazonaws.com/Desarrollo` | público — único punto de entrada |
| BFF | `http://<IP_EC2>:8080` | solo para el API Gateway |
| `ms-pedidos360-orders` | `http://127.0.0.1:8081` | solo loopback |
| `ms-pedidos360-catalog` | `http://127.0.0.1:8082` | solo loopback |

El API Gateway valida el JWT de Entra ID (`issuer` + `audience`), el BFF valida firma, vigencia y **autorización por rol**, y los microservicios resuelven el dominio y la persistencia. Los microservicios no evalúan roles: no ven el token.

### Códigos de estado del dominio

| Código | Cuándo |
| :--- | :--- |
| `400` | Validación de entrada, y **transición de estado inválida** |
| `404` | El pedido o producto no existe |
| `409` | Stock insuficiente, SKU duplicado, conflicto de concurrencia |
| `503` | El microservicio de catálogo no responde |

La transición inválida devuelve `400` porque así lo exige la matriz de pruebas de la pauta (`PUT /api/orders/{id}/ship` con estado no apto). Semánticamente `409` sería más preciso —el recurso existe y la petición está bien formada, lo que falla es el estado— y así está documentado en `ManejadorGlobalErrores`.

## Puesta en marcha

El entorno vive en AWS Academy Learner Lab, cuya sesión caduca cada ~4 horas: la EC2 se detiene sola y la base hay que arrancarla a mano. Estos cinco pasos dejan todo operativo. **Cuentan unos 10 minutos**, casi todos esperando a Oracle.

**1. Iniciar el lab** en AWS Academy y recargar las credenciales:

```powershell
cd C:\dev\pedidos360\aws ; .\01-credenciales-learner-lab.ps1
```

**2. Arrancar la base primero**, que es lo más lento (~5 min):

```powershell
aws rds start-db-instance --db-instance-identifier pedidos360-oracle --region us-east-1
```

**3. Arrancar la instancia** (~1 min; systemd levanta los tres servicios solo):

```powershell
aws ec2 start-instances --instance-ids i-0598cbdf24a3ab50e --region us-east-1
```

**4. Verificar** que los tres respondan:

```powershell
ssh -i C:\dev\pedidos360\aws\pedidos360-key.pem ec2-user@32.194.66.142 "systemctl is-active ms-catalog ms-orders bff"
```

Tres veces `active` y está listo.

**5. Obtener tokens** para probar:

```powershell
cd C:\dev\pedidos360\pruebas ; .\obtener-token.ps1 -Cuenta "Cliente@luissantacruz2026.onmicrosoft.com"
```

Quedan en el portapapeles. Repetir con `Admin@...`.

### Al terminar

```powershell
aws rds stop-db-instance --db-instance-identifier pedidos360-oracle --region us-east-1
```

La EC2 se detiene sola al cerrar el lab; **la base no**, y sigue consumiendo presupuesto.

**Apágala antes de cerrar el lab, no después.** Cuando la sesión del lab termina, AWS aplica la política `voc-cancel-cred` a las credenciales y deniega *todas* las llamadas —incluida la de apagar la base—, así que si se te pasa hay que volver a iniciar el lab solo para eso. El comando devuelve al instante con estado `stopping`: no hace falta esperar a que termine, AWS completa el apagado aunque cierres el lab enseguida.

RDS tampoco permite tenerla detenida más de 7 días: pasado ese plazo AWS la enciende sola. Si entre una sesión y otra pasa más de una semana, hay que entrar a apagarla de nuevo.

### Referencias fijas

| | |
| :--- | :--- |
| URL pública | `https://xpglku1pj5.execute-api.us-east-1.amazonaws.com/Desarrollo` |
| Instancia EC2 | `i-0598cbdf24a3ab50e` — IP elástica `32.194.66.142`, **no cambia** |
| Base de datos | `pedidos360-oracle`, SID `PEDIDOS`, sin acceso público |
| Región | `us-east-1` |

Al conservarse la IP elástica, **el API Gateway nunca hay que reconfigurarlo** entre sesiones del lab.

### Si algo falla

| Síntoma | Causa probable |
| :--- | :--- |
| `ExpiredToken` en cualquier comando | La sesión del lab caducó: volver al paso 1 |
| SSH da timeout | La instancia está detenida, o tu IP pública cambió y el Security Group solo admite la anterior |
| El catálogo responde `[]` | La base no terminó de arrancar; esperar y reiniciar `ms-catalog` |
| Todo responde 401 | Los tokens vencieron: duran una hora |

---

## Estado de verificación

| Qué | Resultado |
| :--- | :--- |
| `mvn clean package` en ambos microservicios | **BUILD SUCCESS** |
| Tests de catálogo (`ProductoServiceTest`, `StockServiceTest`) | **13/13 pasando** |
| Tests de pedidos (`EstadoPedidoTest`, `PedidoServiceTest`) | **44/44 pasando** |
| Arranque real de Tomcat y pruebas HTTP extremo a extremo | **26/26 pasando** |
| Matriz de seguridad contra AWS con tokens reales de Entra ID | **19/19 pasando** |
| Persistencia en Oracle verificada tras reiniciar los servicios | **OK** |
| Sintaxis de los 7 scripts PowerShell | **OK** |
| JSON de la colección Postman | **válido** |

Los 57 tests de Maven verifican la máquina de estados, la atomicidad del descuento de stock, la consolidación de líneas, el congelado de precios y el mapeo JPA. Las 26 comprobaciones de [pruebas/verificar-local.ps1](pruebas/verificar-local.ps1) verifican lo que los tests no pueden: que Tomcat arranca, que la serialización JSON funciona, que la llamada pedidos → catálogo viaja por la red, y que los microservicios no son alcanzables fuera de loopback.

Las 19 comprobaciones de [pruebas/verificar-matriz.ps1](pruebas/verificar-matriz.ps1) recorren la cadena completa —Angular → API Gateway → BFF → microservicio → Oracle— con tokens reales obtenidos por Authorization Code + PKCE:

| Escenario | Esperado | Resultado |
| :--- | :---: | :---: |
| Sin token | 401 | ✅ |
| Token con firma inválida | 401 | ✅ |
| Acceso permitido (rol `Cliente`) | 200 | ✅ |
| Sin permiso de rol (`Cliente` sobre `/accept`) | 403 | ✅ |
| Error de regla de negocio (`/ship` sin aceptar) | 400 | ✅ |
| Preflight CORS sin token | 200 + cabeceras | ✅ |

### Persistencia

La base es **Oracle SE2 en Amazon RDS**, dentro de la misma VPC que la EC2 y sin acceso desde Internet: el Security Group solo admite el puerto 1521 desde el Security Group de la instancia. Se optó por RDS en lugar de Autonomous Database porque el registro en Oracle Cloud exige tarjeta de crédito; el motor, el driver `ojdbc11` y el dialecto de Hibernate son los mismos, y cambiar de una a otra es editar tres variables de entorno.

Prueba de persistencia ejecutada sobre la instancia: se crea un pedido, se acepta (con el consiguiente descuento de stock), se reinician **ambos** microservicios y se verifica que el pedido, su estado y el stock descontado sobreviven, sin que los datos de demostración se dupliquen.

---

## 0. Instalar el toolchain

**JDK 17 o superior.** El `pom` compila con `release 17`, así que un JDK 21 sirve igual:

```powershell
winget install --id EclipseAdoptium.Temurin.21.JDK -e --accept-package-agreements --accept-source-agreements ; winget install --id Amazon.AWSCLI -e
```

**Maven no está en el repositorio de winget**, hay que instalarlo a mano. Sin permisos de administrador:

```powershell
mkdir C:\dev\tools -Force ; curl.exe -sSL -o C:\dev\tools\maven.zip https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip ; Expand-Archive C:\dev\tools\maven.zip -DestinationPath C:\dev\tools -Force ; del C:\dev\tools\maven.zip
```

Y agrégalo al `PATH` de tu usuario de forma permanente:

```powershell
$p = [Environment]::GetEnvironmentVariable('Path','User'); [Environment]::SetEnvironmentVariable('Path', $p.TrimEnd(';') + ';C:\dev\tools\apache-maven-3.9.9\bin', 'User')
```

Cierra y vuelve a abrir PowerShell para que tome el `PATH`, y comprueba:

```bash
java -version; mvn -v; aws --version
```

### Política de ejecución de PowerShell

Windows bloquea los `.ps1` por defecto (`Restricted`). Para poder correr los scripts de este repo:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

No necesita administrador. `RemoteSigned` permite scripts locales como estos y sigue bloqueando los descargados sin firmar. Si prefieres no cambiar nada, usa `powershell -ExecutionPolicy Bypass -File .\script.ps1` en cada invocación.

---

## 1. Compilar y correr en local

```bash
cd ms-pedidos360-catalog; mvn clean package
```

```bash
cd ms-pedidos360-orders; mvn clean package
```

Los tests corren solos en el `package`. Si quieres saltarlos, agrega `-DskipTests`.

> **Ojo con la ruta**: si el proyecto queda en una carpeta muy profunda, Windows corta las rutas en 260 caracteres y la compilación falla con errores raros de "path not found". Déjalo en algo corto como `C:\dev\pedidos360`.

En dos terminales separadas — **el catálogo primero**, porque pedidos lo consulta al arrancar un pedido:

```bash
java -jar ms-pedidos360-catalog/target/ms-pedidos360-catalog.jar
```

```bash
java -jar ms-pedidos360-orders/target/ms-pedidos360-orders.jar
```

El perfil por defecto es `dev`: base **H2 en memoria**, sin dependencias externas, con siete productos de demostración precargados. Consola web en `http://localhost:8082/h2-console` (JDBC URL `jdbc:h2:mem:catalogdb`, usuario `sa`, sin contraseña).

Prueba rápida sin pasar por AWS:

```bash
curl http://localhost:8082/api/catalog
```

```bash
curl -X POST http://localhost:8081/api/orders -H "Content-Type: application/json" -d "{\"clienteEmail\":\"test@duoc.cl\",\"items\":[{\"productoId\":1,\"cantidad\":2}]}"
```

---

## 2. Pasar a Oracle Autonomous Database

1. Crea la ADB en OCI (Always Free sirve) y descarga el wallet.
2. Descomprime el wallet, por ejemplo en `C:\oracle\wallet`.
3. Define las variables de entorno **sin escribir credenciales en ningún archivo del proyecto**:

```powershell
$env:TNS_ADMIN = "C:\oracle\wallet"
$env:ORACLE_JDBC_URL = "jdbc:oracle:thin:@pedidos360_high?TNS_ADMIN=C:\oracle\wallet"
$env:ORACLE_USER = "ADMIN"
$env:ORACLE_PASSWORD = Read-Host "Password de Oracle"
```

4. Arranca con el perfil `oracle`:

```bash
java -jar ms-pedidos360-catalog/target/ms-pedidos360-catalog.jar --spring.profiles.active=oracle
```

Hibernate crea solo las tablas (`PRODUCTO`, `PEDIDO`, `PEDIDO_ITEM`) y las secuencias. El alias `pedidos360_high` sale de `tnsnames.ora` dentro del wallet — ábrelo y usa el que corresponda a tu base.

---

## 3. Desplegar en AWS (Learner Lab)

### Cada vez que inicias el lab

```powershell
cd aws; .\01-credenciales-learner-lab.ps1
```

Pega el bloque de *AWS Details → AWS CLI*. El script escribe `~/.aws/credentials`, verifica la identidad y te dice si la cuenta permite Elastic IP.

### Primera vez

```powershell
.\00-crear-ec2.ps1
```

Crea el Security Group (solo `8080` al mundo, `22` a tu IP), el par de llaves y la instancia con Java 17 y las unidades de systemd ya listas.

```powershell
.\02-desplegar-api-gateway.ps1 -DestinoBff "http://<IP_QUE_IMPRIMIO>:8080"
```

Crea la HTTP API, el JWT Authorizer de Entra ID, las 8 rutas funcionales protegidas, las 6 rutas `OPTIONS` públicas y el stage con auto-deploy. Es idempotente: puedes volver a correrlo sin duplicar nada.

Las 8 rutas son exactamente las que el frontend consume: `GET`/`POST /api/orders`, los cuatro cambios de estado (`accept`, `prepare`, `ship`, `deliver`) y `GET`/`POST /api/catalog`. Cada una tiene su `OPTIONS` salvo las que comparten ruta base.

Al final imprime la **URL de invocación**, que es lo único que tu compañero necesita.

### En las sesiones siguientes

**No hace falta.** La instancia tiene una IP elástica (`32.194.66.142`), así que conserva su dirección entre sesiones del lab y el API Gateway nunca se toca.

Si alguna vez se pierde la IP elástica, un solo comando reapunta las 14 integraciones:

```powershell
.\03-actualizar-destino-bff.ps1 -DesdeInstancia i-0abc123def456
```

### Subir los JAR

```bash
scp -i aws/pedidos360-key.pem ms-pedidos360-catalog/target/ms-pedidos360-catalog.jar ms-pedidos360-orders/target/ms-pedidos360-orders.jar ec2-user@<IP>:/tmp/
```

```bash
ssh -i aws/pedidos360-key.pem ec2-user@<IP> "sudo mv /tmp/*.jar /opt/pedidos360/bin/ && sudo chown pedidos360:pedidos360 /opt/pedidos360/bin/*.jar && sudo systemctl enable --now ms-catalog ms-orders bff"
```

Ver logs:

```bash
ssh -i aws/pedidos360-key.pem ec2-user@<IP> "sudo journalctl -u ms-orders -n 50 --no-pager"
```

### Plan B: sin EC2

Si el lab se pone difícil el día de la defensa, corre todo local y expón solo el BFF:

```bash
cloudflared.exe tunnel --url http://localhost:8080
```

```powershell
.\03-actualizar-destino-bff.ps1 -NuevoDestinoBff "https://xxxx.trycloudflare.com"
```

---

## 4. Pruebas

### Tests automatizados (sin AWS ni Entra ID)

```bash
mvn test
```

57 tests que cubren la máquina de estados completa, la atomicidad del descuento de stock, la consolidación de líneas repetidas, el congelado de precios, la baja lógica y los filtros de listado. `PedidoServiceTest` simula el microservicio de catálogo con un mock, así que corre sin levantar nada más.

Sirven para la defensa: son la evidencia de que las reglas de negocio funcionan, independiente de que la infraestructura esté arriba.

### Verificación de punta a punta en local (sin AWS ni Entra ID)

```bash
cd C:\dev\pedidos360\pruebas ; .\verificar-local.ps1
```

Levanta los dos microservicios, ejecuta 26 comprobaciones sobre HTTP real y los apaga al terminar. A diferencia de `mvn test`, esto sí prueba que Tomcat arranca, que la serialización JSON funciona y que la comunicación pedidos → catálogo ocurre por la red.

Comprueba entre otras cosas que crear un pedido **no** descuenta stock, que aceptarlo **sí** lo descuenta, que cancelar lo repone, que no se puede despachar sin aceptar, y que los microservicios **no** son accesibles desde fuera de loopback.

Córrelo antes de subir nada a AWS: depurar en tu máquina es mucho más rápido que por SSH en una EC2.

### Token de Entra ID

```powershell
cd pruebas; .\obtener-token.ps1 -Cuenta "Cliente@luissantacruz2026.onmicrosoft.com"
```

Pide el token, lo copia al portapapeles y **diagnostica si va a pasar el authorizer de AWS**: revisa `iss`, `aud` y `scp`, y si algo está mal te dice exactamente qué tiene que cambiar tu compañero en Entra ID.

Luego importa en Postman `Pedidos360.postman_collection.json` y `Pedidos360.postman_environment.json`, rellena `baseUrl`, `tokenCliente` y `tokenAdmin`, y corre la carpeta **Matriz de seguridad** con el Collection Runner.

| Escenario | Esperado | Quién valida |
| :--- | :--- | :--- |
| Sin token | 401 | API Gateway |
| Firma inválida | 401 | API Gateway |
| Preflight `OPTIONS` | 200 + headers CORS | API Gateway / BFF |
| Rol `Cliente` en `/accept` | 403 | BFF |
| `GET /api/orders` con token válido | 200 + JSON | Flujo completo |

La carpeta **Flujo de pedido** recorre la máquina de estados completa e incluye los dos casos de regla de negocio: despachar sin aceptar (400, por la matriz de la pauta) y stock insuficiente (409).

---

## 5. Publicar en GitHub

El proyecto vive en `C:\dev\pedidos360` y **conviene dejarlo ahí**, no moverlo a `Documents\GitHub`: esa ruta tiene espacios y tilde, y sumada a los paquetes Java profundos vuelve a superar el límite de 260 caracteres de Windows que ya rompió una compilación.

```bash
winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
```

Reabre PowerShell y, la primera vez, identifícate:

```bash
git config --global user.name "Vicente Farias" ; git config --global user.email "vifarias304@gmail.com"
```

Inicializa y haz el primer commit:

```bash
cd C:\dev\pedidos360 ; git init -b main ; git add . ; git commit -m "EP1 DSY1107: microservicios, API Gateway y pruebas"
```

Antes de subir, confirma que no se coló ninguna llave:

```bash
git ls-files | Select-String -Pattern "\.pem$|wallet|credentials|salida-despliegue"
```

Ese comando **no debe devolver nada**. Si devuelve algo, no hagas push y avísame.

Luego crea el repo en github.com y conéctalo:

```bash
git remote add origin https://github.com/<TU_USUARIO>/pedidos360-ep1.git ; git push -u origin main
```

### Sobre hacerlo público

En el repositorio quedan el Tenant ID y los dos Client ID de Entra ID. **No son secretos** — son identificadores públicos que el frontend expone igual en cada petición — así que un repo público no filtra nada peligroso. Lo que sí son secretos y por eso están en `.gitignore`: las llaves `.pem`, el wallet de Oracle, las credenciales de AWS y el archivo `entorno`.

Este repositorio quedó **público** para que el docente pueda revisarlo sin gestión de permisos, que es lo que pide la entrega. La alternativa —privado con el docente como colaborador— protege algo más, porque es un tenant de pruebas con cuentas reales y no gana nada estando indexado por Google. Se descartó solo porque depende de que el docente acepte la invitación a tiempo.

---

### Repositorios del equipo

| Componente | Repositorio | Responsable |
| :--- | :--- | :--- |
| AWS + microservicios + persistencia | https://github.com/VicenteJFV/pedidos360-ep1 | Vicente |
| Frontend Angular + MSAL | https://github.com/Zerete/pedidos360_frontend | Zerete |
| BFF Spring Boot | https://github.com/Zerete/pedidos360-bff | Zerete |

Los tres son públicos, para que el docente pueda revisarlos sin gestión de permisos.

Los repositorios están separados a propósito: son responsabilidades distintas. El único punto donde se tocan es el despliegue — **el BFF se compila en la máquina de su autor y el JAR se copia a mi EC2**, porque el `user-data` instala `java-17-amazon-corretto-headless`, que es solo runtime y no trae `javac` ni Maven.

```bash
scp -i aws\pedidos360-key.pem bff-pedidos360.jar ec2-user@<IP>:/tmp/
```

```bash
ssh -i aws\pedidos360-key.pem ec2-user@<IP> "sudo mv /tmp/bff-pedidos360.jar /opt/pedidos360/bin/ && sudo chown pedidos360:pedidos360 /opt/pedidos360/bin/bff-pedidos360.jar && sudo systemctl restart bff"
```

Si prefieren compilar en la instancia, hay que agregar `java-17-amazon-corretto-devel` y `maven` al `dnf install` de [aws/ec2-user-data.sh](aws/ec2-user-data.sh).

---

## 6. Decisiones de diseño

**Los microservicios no validan JWT.** La autenticación es del API Gateway y la autorización por rol es del BFF. Lo que impide llamarlos directamente es la red: escuchan en `127.0.0.1` (`server.address`) y sus puertos no están en el Security Group. Defensa en profundidad sin duplicar lógica de seguridad en tres capas.

**El stock se descuenta al aceptar, no al crear.** Crear un pedido solo verifica disponibilidad de forma informativa. Un carrito abandonado no debe bloquear inventario.

**El descuento de stock es atómico.** Si una sola línea no alcanza, no se descuenta ninguna y se devuelve 409 con el detalle de todas las que fallaron. Las filas se bloquean con `SELECT ... FOR UPDATE` siempre en orden de id ascendente, para que dos reservas concurrentes se serialicen en vez de provocar un deadlock.

**Las transiciones de estado viven en el enum `EstadoPedido`**, no repartidas por los servicios. Es la única fuente de verdad y hace estructuralmente imposible despachar sin haber aceptado.

**En `accept` se persiste antes de llamar al catálogo.** Si el catálogo responde 409 por falta de stock, la excepción propaga, la transacción hace rollback y el pedido vuelve a `CREADO`. Queda una ventana residual conocida — si el catálogo descuenta y el commit local falla después — que resolverla de verdad exigiría un patrón saga con mensajería, fuera del alcance de esta entrega. Está documentado en el código.

**Los precios se congelan en `PEDIDO_ITEM`.** Si mañana sube el precio en el catálogo, los pedidos históricos no cambian.

**Los productos se dan de baja lógicamente**, nunca se borran: los pedidos históricos los referencian.
