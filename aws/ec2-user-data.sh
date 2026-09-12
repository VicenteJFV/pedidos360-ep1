#!/bin/bash
# Aprovisionamiento de la instancia EC2 para Pedidos360 (EP1 DSY1107).
# Amazon Linux 2023. Se ejecuta una sola vez, al primer arranque de la instancia.

set -euxo pipefail
exec > >(tee /var/log/pedidos360-userdata.log) 2>&1

echo "=== Instalando Amazon Corretto 17 ==="
dnf install -y java-17-amazon-corretto-headless

echo "=== Creando estructura ==="
useradd --system --create-home --shell /sbin/nologin pedidos360 || true
mkdir -p /opt/pedidos360/{bin,logs,wallet}
chown -R pedidos360:pedidos360 /opt/pedidos360

# Variables compartidas por los tres servicios. Las credenciales de Oracle se
# agregan a este archivo despues, NUNCA se hornean en la imagen ni en el user-data.
cat > /opt/pedidos360/entorno <<'EOF'
SPRING_PROFILE=dev
# Para Oracle, cambiar a: SPRING_PROFILE=oracle y descomentar lo siguiente
# TNS_ADMIN=/opt/pedidos360/wallet
# ORACLE_JDBC_URL=jdbc:oracle:thin:@pedidos360_high?TNS_ADMIN=/opt/pedidos360/wallet
# ORACLE_USER=ADMIN
# ORACLE_PASSWORD=
EOF
chmod 600 /opt/pedidos360/entorno
chown pedidos360:pedidos360 /opt/pedidos360/entorno

# ---------------------------------------------------------------------------
# Unidades systemd. Los microservicios quedan atados a loopback; solo el BFF
# escucha en todas las interfaces, que es lo unico que el Security Group abre.
# ---------------------------------------------------------------------------

crear_unidad() {
  local nombre="$1"
  local jar="$2"
  local extra="$3"

  cat > "/etc/systemd/system/${nombre}.service" <<EOF
[Unit]
Description=Pedidos360 - ${nombre}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pedidos360
WorkingDirectory=/opt/pedidos360
EnvironmentFile=/opt/pedidos360/entorno
${extra}
ExecStart=/usr/bin/java -Xms128m -Xmx320m -jar /opt/pedidos360/bin/${jar}
SuccessExitStatus=143
Restart=on-failure
RestartSec=10
StandardOutput=append:/opt/pedidos360/logs/${nombre}.log
StandardError=append:/opt/pedidos360/logs/${nombre}.log

[Install]
WantedBy=multi-user.target
EOF
}

crear_unidad "ms-catalog" "ms-pedidos360-catalog.jar" "Environment=MS_BIND_ADDRESS=127.0.0.1"
crear_unidad "ms-orders"  "ms-pedidos360-orders.jar"  "Environment=MS_BIND_ADDRESS=127.0.0.1
Environment=CATALOG_BASE_URL=http://127.0.0.1:8082"
crear_unidad "bff"        "bff-pedidos360.jar"        "Environment=SERVER_ADDRESS=0.0.0.0"

systemctl daemon-reload

echo "=== Listo ==="
echo "Copia los JAR a /opt/pedidos360/bin/ y luego:"
echo "  sudo systemctl enable --now ms-catalog ms-orders bff"
