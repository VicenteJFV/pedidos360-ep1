# Pedidos360 — AWS, API Gateway y Microservicios (EP1 DSY1107)

Mi parte de la evaluación: los dos microservicios de negocio, la persistencia en Oracle y toda la infraestructura AWS.

```
pedidos360/
├── ms-pedidos360-orders/     Microservicio principal (8081) — pedidos y máquina de estados
├── ms-pedidos360-catalog/    Microservicio de catálogo (8082) — productos y stock
├── aws/                      Scripts de infraestructura y API Gateway
├── pruebas/                  Obtención de token y colección Postman
└── CONTRATO-EQUIPO.md        Lo que hay que coordinar con el compañero
```

## Estado de verificación

| Qué | Resultado |
| :--- | :--- |
| `mvn clean package` en ambos microservicios | **BUILD SUCCESS** |
| Tests de catálogo (`ProductoServiceTest`, `StockServiceTest`) | **13/13 pasando** |
| Tests de pedidos (`EstadoPedidoTest`, `PedidoServiceTest`) | **44/44 pasando** |
| Sintaxis de los 5 scripts PowerShell | **OK** |
| JSON de la colección Postman | **válido** |
| Arranque real de Tomcat y pruebas HTTP extremo a extremo | **no ejecutado** |
| Scripts de AWS contra una cuenta real | **no ejecutados** |

Los 57 tests se ejecutaron con JDK 17 y Maven portables y verifican la máquina de estados completa, la atomicidad del descuento de stock, la consolidación de líneas, el congelado de precios y el mapeo JPA contra H2.

Lo que queda sin verificar es el arranque HTTP — el entorno donde generé esto bloquea la creación de sockets, así que Tomcat no puede levantar — y todo lo que toca AWS, que necesita tus credenciales del lab. Ambas cosas las compruebas tú con los pasos de abajo.

---

## 0. Instalar el toolchain

```powershell
winget install --id EclipseAdoptium.Temurin.17.JDK -e --accept-package-agreements --accept-source-agreements
```

```powershell
winget install --id Apache.Maven -e ; winget install --id Amazon.AWSCLI -e
```

Cierra y vuelve a abrir PowerShell para que tome el `PATH`, y comprueba:

```bash
java -version; mvn -v; aws --version
```

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

Crea la HTTP API, el JWT Authorizer de Entra ID, las 13 rutas funcionales protegidas, las 9 rutas `OPTIONS` públicas y el stage con auto-deploy. Es idempotente: puedes volver a correrlo sin duplicar nada.

Al final imprime la **URL de invocación**, que es lo único que tu compañero necesita.

### En las sesiones siguientes

La instancia arranca con otra IP. Un solo comando arregla las 22 integraciones:

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
cd pruebas; .\obtener-token.ps1 -Usuario "Cliente@luissantacruz2026.onmicrosoft.com"
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

La carpeta **Flujo de pedido** recorre la máquina de estados completa e incluye los dos casos de regla de negocio: despachar sin aceptar (409) y stock insuficiente (409).

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

Aun así, para trabajo de curso **recomiendo repo privado** y agregar a tu compañero y al docente como colaboradores. Es un tenant de pruebas con cuentas de usuario reales, y no gana nada estando indexado por Google.

---

### Repositorios del equipo

| Componente | Repositorio | Responsable |
| :--- | :--- | :--- |
| AWS + microservicios + persistencia | https://github.com/VicenteJFV/pedidos360-ep1 (privado) | Vicente |
| Frontend Angular + MSAL | https://github.com/Zerete/pedidos360_frontend (público) | Zerete |
| BFF Spring Boot | por definir | Zerete |

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
