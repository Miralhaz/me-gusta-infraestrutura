#!/bin/bash
set -euo pipefail

# Define o hostname da instancia ANTES de qualquer operacao de Docker/Swarm.
# O Docker Swarm registra cada no com o hostname do SO, portanto ele precisa
# bater com os nomes esperados pelo label-nodes.sh (ex.: megusta-prod-us1-backend-a),
# senao os placement.constraints por label nunca casam e os servicos ficam Pending.
HOSTNAME_FULL="megusta-prod-us1-${hostname}"
hostnamectl set-hostname "$HOSTNAME_FULL" || echo "AVISO: falha ao definir hostname" >&2
echo "$HOSTNAME_FULL" > /etc/hostname
grep -q "$HOSTNAME_FULL" /etc/hosts || echo "127.0.0.1 $HOSTNAME_FULL" >> /etc/hosts

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Instalacao robusta de pacotes:
#  - apt_update/apt_install esperam o lock do dpkg (cloud-init/unattended-
#    upgrades) por ate 180s e retentam ate 10x (a rota via NAT Gateway pode
#    demorar a ficar disponivel no boot das subnets privadas);
#  - sem isto, um unico "apt-get update" falho derrubava todo o script por
#    causa do "set -e" e NENHUM pacote era instalado.
# ---------------------------------------------------------------------------
apt_update() {
    for i in $(seq 1 10); do
        if apt-get -o DPkg::Lock::Timeout=180 update -y; then
            return 0
        fi
        echo "apt-get update falhou (tentativa $i/10), aguardando rede/apt..."
        sleep 15
    done
    echo "ERRO: apt-get update falhou apos 10 tentativas" >&2
    return 1
}

apt_install() {
    for i in $(seq 1 10); do
        if apt-get -o DPkg::Lock::Timeout=180 install -y "$@"; then
            return 0
        fi
        echo "apt-get install $* falhou (tentativa $i/10), aguardando..."
        sleep 15
        apt-get -o DPkg::Lock::Timeout=180 update -y || true
    done
    echo "ERRO: apt-get install $* falhou apos 10 tentativas" >&2
    return 1
}

# So comeca a instalar quando houver acesso REAL a Internet (NAT pronto)
for i in $(seq 1 60); do
    if curl -fsS --max-time 5 -o /dev/null http://archive.ubuntu.com/ubuntu/; then
        echo "Internet disponivel apos $i tentativa(s)"
        break
    fi
    echo "Sem acesso a Internet ainda (tentativa $i/60)..."
    sleep 10
done

apt_update
apt_install docker.io awscli gpg curl git nodejs npm nginx

# Ensure node is available as 'node' (Ubuntu ships as nodejs)
if ! command -v node >/dev/null 2>&1 && command -v nodejs >/dev/null 2>&1; then
    ln -sf "$(command -v nodejs)" /usr/local/bin/node
fi

# Verify critical packages installed
# NAO usar "dpkg -l | grep -q" aqui: sob "set -o pipefail" o grep -q sai no
# primeiro match, o dpkg recebe SIGPIPE (141), o pipeline falha e o script
# abortava dizendo que o pacote nao foi instalado (mesmo estando instalado).
for pkg in docker.io git curl nginx nodejs npm; do
    pkg_status="$(dpkg-query -W -f='$${Status}' "$pkg" 2>/dev/null || true)"
    if [ "$pkg_status" != "install ok installed" ]; then
        echo "ERRO: Pacote $pkg não instalado após tentativas" >&2
        exit 1
    fi
done
# Also verify node is available
if ! command -v node >/dev/null 2>&1; then
    echo "ERRO: node não encontrado após instalação" >&2
    exit 1
fi

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Install Fluent Bit - caminhos de fallback com a versao fixada pelo Terraform
# (${FLUENTBIT_VERSION} via templatefile). O GitHub releases NAO possui assets
# de binario, por isso todos os fallbacks baixam o .deb direto do repo oficial.
FLUENTBIT_INSTALLED=false
FLUENTBIT_DEB_URL="https://packages.fluentbit.io/ubuntu/jammy/pool/main/f/fluent-bit/fluent-bit_${FLUENTBIT_VERSION}_amd64.deb"

# Method 1: Try official Fluent Bit repository
echo "Tentando instalar Fluent Bit via repositorio oficial..."
for i in 1 2 3; do
    rm -f /usr/share/keyrings/fluentbit.gpg
    if curl -fsSL https://packages.fluentbit.io/fluentbit.key | gpg --dearmor -o /usr/share/keyrings/fluentbit.gpg 2>/dev/null && \
       echo "deb [signed-by=/usr/share/keyrings/fluentbit.gpg] https://packages.fluentbit.io/ubuntu/jammy jammy main" | tee /etc/apt/sources.list.d/fluentbit.list >/dev/null && \
       apt-get update -y 2>/dev/null && \
       apt-get -o DPkg::Lock::Timeout=180 install -y "fluent-bit=${FLUENTBIT_VERSION}" 2>/dev/null; then
      FLUENTBIT_INSTALLED=true
      echo "Fluent Bit instalado via repositorio oficial"
      break
    else
         echo "Tentativa $i falhou, aguardando..."
         sleep 10
    fi
done

# Method 2: Download direto do .deb no repo oficial (nao depende do apt resolver repo)
if [ "$FLUENTBIT_INSTALLED" = false ]; then
    echo "Fallback: baixando .deb ${FLUENTBIT_VERSION} direto do repo oficial..."
    rm -f /etc/apt/sources.list.d/fluentbit.list
    apt-get -o DPkg::Lock::Timeout=180 update -y || true
    if curl -fsSL "$FLUENTBIT_DEB_URL" -o /tmp/fluent-bit.deb && \
       apt-get -o DPkg::Lock::Timeout=180 install -y /tmp/fluent-bit.deb; then
        FLUENTBIT_INSTALLED=true
        echo "Fluent Bit ${FLUENTBIT_VERSION} instalado via .deb direto do repo oficial"
    fi
fi

# Method 3: versao alternativa (3.1.4) via .deb direto do repo oficial
if [ "$FLUENTBIT_INSTALLED" = false ]; then
    echo "Fallback: tentando versao alternativa 3.1.4 via .deb direto..."
    if curl -fsSL "https://packages.fluentbit.io/ubuntu/jammy/pool/main/f/fluent-bit/fluent-bit_3.1.4_amd64.deb" -o /tmp/fluent-bit-3.1.4.deb && \
       apt-get -o DPkg::Lock::Timeout=180 install -y /tmp/fluent-bit-3.1.4.deb; then
        FLUENTBIT_INSTALLED=true
        echo "Fluent Bit 3.1.4 instalado via .deb direto do repo oficial"
    fi
fi

# Verify installation
if [ "$FLUENTBIT_INSTALLED" = false ]; then
    echo "ERRO: Falha ao instalar Fluent Bit apos todas as tentativas" >&2
    exit 1
fi

# Verify binary exists (check common locations including official repo path)
FLUENTBIT_BIN=""
for path in /usr/bin/fluent-bit /opt/fluent-bit/bin/fluent-bit /usr/local/bin/fluent-bit; do
    if [ -x "$path" ]; then
        FLUENTBIT_BIN="$path"
        break
    fi
done

if [ -z "$FLUENTBIT_BIN" ]; then
    # Last resort: check PATH
    if command -v fluent-bit &> /dev/null; then
        FLUENTBIT_BIN="fluent-bit"
    fi
fi

if [ -z "$FLUENTBIT_BIN" ]; then
    echo "ERRO: Binary fluent-bit nao encontrado apos instalacao" >&2
    exit 1
fi

echo "Fluent Bit versao: $($FLUENTBIT_BIN --version)"

# Ensure fluent-bit is in PATH for all users (symlink + profile.d)
if [ -f /opt/fluent-bit/bin/fluent-bit ] && [ ! -f /usr/local/bin/fluent-bit ]; then
    ln -sf /opt/fluent-bit/bin/fluent-bit /usr/local/bin/fluent-bit
fi
echo 'export PATH="/opt/fluent-bit/bin:$PATH"' > /etc/profile.d/fluent-bit.sh
chmod +x /etc/profile.d/fluent-bit.sh

# Create Fluent Bit configuration directory
mkdir -p /etc/fluent-bit/config

# Fluent Bit main configuration
cat > /etc/fluent-bit/fluent-bit.conf <<'FLUENT_EOF'
[SERVICE]
    Flush        5
    Log_Level    info
    Daemon       off
    Parsers_File parsers.conf
    HTTP_Server  On
    HTTP_Listen  0.0.0.0
    HTTP_Port    2020
    Health_Check On

# Docker container logs
[INPUT]
    Name              tail
    Tag               docker.*
    Path              /var/lib/docker/containers/*/*.log
    Parser            docker
    DB                /var/log/fluent-bit/docker.db
    Mem_Buf_Limit     50MB
    Skip_Long_Lines   On
    Refresh_Interval  10

# Systemd journal logs
[INPUT]
    Name              systemd
    Tag               systemd.docker
    Systemd_Filter    _SYSTEMD_UNIT=docker.service
    DB                /var/log/fluent-bit/systemd.db

[INPUT]
    Name              systemd
    Tag               systemd.ssh
    Systemd_Filter    _SYSTEMD_UNIT=ssh.service
    DB                /var/log/fluent-bit/sshd.db

[INPUT]
    Name              systemd
    Tag               systemd.kernel
    Systemd_Filter    _TRANSPORT=kernel
    DB                /var/log/fluent-bit/kernel.db

# Nginx access logs
[INPUT]
    Name              tail
    Tag               nginx.access
    Path              /var/log/nginx/access.log
    Parser            nginx
    DB                /var/log/fluent-bit/nginx_access.db
    Mem_Buf_Limit     10MB
    Refresh_Interval  10

# Nginx error logs
[INPUT]
    Name              tail
    Tag               nginx.error
    Path              /var/log/nginx/error.log
    Parser            nginx
    DB                /var/log/fluent-bit/nginx_error.db
    Mem_Buf_Limit     10MB
    Refresh_Interval  10

# Application logs (custom path for project logs)
[INPUT]
    Name              tail
    Tag               app.project
    Path              /var/log/megusta/*.log
    Parser            json
    DB                /var/log/fluent-bit/app_project.db
    Mem_Buf_Limit     10MB
    Refresh_Interval  10
    Skip_Long_Lines   On

# Output to S3 (Bronze/Raw bucket) - usa credenciais do Instance Profile automaticamente
[OUTPUT]
    Name            s3
    Match           *
    bucket          ${raw_bucket}
    region          us-east-1
    total_file_size 50M
    upload_timeout  120
    use_put_object  On
    s3_key_format   /logs/$TAG/%Y/%m/%d/%H/%M/%S_${hostname}.log
    store_dir       /var/log/fluent-bit/s3
    compression     gzip
FLUENT_EOF

# Custom parsers for Docker, Nginx, and JSON
cat > /etc/fluent-bit/parsers.conf <<'PARSER_EOF'
[PARSER]
    Name        docker
    Format      json
    Time_Key    time
    Time_Format %Y-%m-%dT%H:%M:%S.%LZ
    Time_Keep   On

[PARSER]
    Name   nginx
    Format regex
    Regex  ^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$
    Time_Key time
    Time_Format %d/%b/%Y:%H:%M:%S %z

[PARSER]
    Name   syslog
    Format regex
    Regex  ^(?<time>\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(?<host>\S+)\s+(?<ident>[^:]+):\s*(?<message>.*)$
    Time_Key time
    Time_Format %b %d %H:%M:%S

[PARSER]
    Name        json
    Format      json
    Time_Key    timestamp
    Time_Format %Y-%m-%dT%H:%M:%S.%LZ
    Time_Keep   On
PARSER_EOF

# Create log directories
mkdir -p /var/log/fluent-bit/s3
mkdir -p /var/log/nginx
mkdir -p /var/log/megusta

# Start Fluent Bit
systemctl start fluent-bit
systemctl enable fluent-bit

# Install Java 21 for Spring Boot.
# IMPORTANTE: Ubuntu 22.04 (jammy) NAO possui openjdk-21 nos repositorios
# oficiais. Tentamos o pacote padrao primeiro e, se indisponivel, instalamos
# o Eclipse Temurin 21 via repo oficial da Adoptium (mesmo binario OpenJDK).
if apt-cache show openjdk-21-jdk >/dev/null 2>&1; then
    apt_install openjdk-21-jdk
else
    echo "openjdk-21-jdk indisponivel no repositorio padrao do jammy. Instalando Eclipse Temurin 21..."
    install -m 0755 -d /etc/apt/keyrings
    rm -f /etc/apt/keyrings/adoptium.asc
    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public -o /etc/apt/keyrings/adoptium.asc
    echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb jammy main" > /etc/apt/sources.list.d/adoptium.list
    apt_update
    apt_install temurin-21-jdk
fi

# Verificacao dura: Java 21 precisa responder.
# Sem pipe: "java -version | head -n 1" tambem dispara SIGPIPE sob pipefail.
JAVA_FIRST_LINE="$(java -version 2>&1 || true)"
echo "Java instalado: $JAVA_FIRST_LINE"
case "$JAVA_FIRST_LINE" in
    *'version "21'*) : ;;
    *)
        echo "ERRO: Java 21 nao esta instalado (obtido: $JAVA_FIRST_LINE)" >&2
        exit 1
        ;;
esac

# Create a simple health check endpoint for the backend
mkdir -p /opt/megusta-backend
cat > /opt/megusta-backend/health.sh <<'HEALTH_EOF'
#!/bin/bash
echo "Backend ${hostname} - Healthy"
HEALTH_EOF
chmod +x /opt/megusta-backend/health.sh

# Systemd service for backend health check (port 8080)
cat > /etc/systemd/system/megusta-backend-health.service <<'SVC_EOF'
[Unit]
Description=MeGusta Backend Health Check
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -m http.server 8080 --directory /opt/megusta-backend
Restart=always
User=ubuntu

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl start megusta-backend-health
systemctl enable megusta-backend-health

# Start Nginx (health check endpoint)
systemctl start nginx
systemctl enable nginx
echo "<html><body><h1>Backend ${hostname} - Healthy</h1></body></html>" > /var/www/html/index.html