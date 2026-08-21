set -euo pipefail  #Qualquer erro aborta o script"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

ENDPOINT_URL="http://localhost:4566"
AWSLOCAL="aws --endpoint-url=${ENDPOINT_URL} --region ${AWS_DEFAULT_REGION}"

PROJETO="megusta-infra-localstack"
PROPRIETARIO="grupo1-26"

VPC_CIDR="10.0.0.0/24"
SUB_PUB_A_CIDR="10.0.0.0/26"          # us-east-1a (pública)
SUB_PUB_B_CIDR="10.0.0.64/26"         # us-east-1b (pública)
SUB_PRIV_WEB_A_CIDR="10.0.0.128/27"   # us-east-1a (web)
SUB_PRIV_WEB_B_CIDR="10.0.0.160/27"   # us-east-1b (web)
SUB_PRIV_BACKEND_CIDR="10.0.0.192/27" # backend
SUB_PRIV_DB_CIDR="10.0.0.224/27"      # database

AZ_A="us-east-1a"
AZ_B="us-east-1b"

#Cria um arquivo de log separado pelo timestamp do mesmo
LOG_FILE="./infra_deploy_$(date +%Y%m%d_%H%M%S).log"

#Função de log com timestamp e nível de log (INFO, ERROR, etc.)
log() {
    local nivel="$1"; shift
    local msg="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${nivel}] ${msg}" | tee -a "${LOG_FILE}"
}

#Divide a implementação por pausas (do 1 ao 5)
pausa() {
    echo ""
    log "INFO" "=============================================="
    log "INFO" "$1"
    log "INFO" "=============================================="
}

#Retorna o SubnetId se já existir uma sub-rede com esse CIDR
#dentro da VPC informada; senão retorna vazio.
buscar_subnet_existente() {
    local vpc_id="$1"
    local cidr="$2"
    ${AWSLOCAL} ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=cidr-block,Values=${cidr}" \
        --query "Subnets[0].SubnetId" --output text 2>/dev/null | grep -v '^None$' || true
}

#Retorna o GroupId se já existir um Security Group com esse
#nome dentro da VPC informada; senão retorna vazio.
buscar_sg_existente() {
    local vpc_id="$1"
    local nome="$2"
    ${AWSLOCAL} ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=group-name,Values=${nome}" \
        --query "SecurityGroups[0].GroupId" --output text 2>/dev/null | grep -v '^None$' || true
}

# -----------------------------------------------------------------------------
# PAUSA 1
# -----------------------------------------------------------------------------
pausa "PAUSA 1: Verificação de Prontidão"

log "INFO" "Executado por: $(whoami) | Ambiente: LOCALSTACK (teste)"

if ! command -v aws &> /dev/null; then
    log "ERROR" "AWS CLI não encontrada. Instale antes de continuar."
    exit 1
fi

log "INFO" "Validando conectividade com o LocalStack em ${ENDPOINT_URL}..."
if ! ${AWSLOCAL} sts get-caller-identity > /dev/null 2>&1; then
    log "ERROR" "Não foi possível autenticar/conectar ao LocalStack. O container está de pé? (docker compose up -d)"
    exit 1
fi
log "INFO" "Conexão validada com sucesso (aws sts get-caller-identity OK)."

# -----------------------------------------------------------------------------
# PAUSA 2
# -----------------------------------------------------------------------------
pausa "PAUSA 2: Fundação da Rede Pública"

#VPC (Verifica se já existe antes de criar)
log "INFO" "Verificando se a VPC do projeto já existe..."
VPC_ID=$(${AWSLOCAL} ec2 describe-vpcs \
    --filters "Name=tag:Projeto,Values=${PROJETO}" \
    --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")

if [ "${VPC_ID}" == "None" ] || [ -z "${VPC_ID}" ]; then
    log "INFO" "Criando VPC (${VPC_CIDR})..."
    VPC_ID=$(${AWSLOCAL} ec2 create-vpc \
        --cidr-block "${VPC_CIDR}" \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJETO}-vpc},{Key=Projeto,Value=${PROJETO}},{Key=Proprietario,Value=${PROPRIETARIO}}]" \
        --query "Vpc.VpcId" --output text)
    log "INFO" "VPC criada: ${VPC_ID}"
else
    log "INFO" "VPC já existente, reutilizando: ${VPC_ID}"
fi

#Internet Gateway
log "INFO" "Verificando Internet Gateway..."
IGW_ID=$(${AWSLOCAL} ec2 describe-internet-gateways \
    --filters "Name=tag:Projeto,Values=${PROJETO}" \
    --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || echo "None")

if [ "${IGW_ID}" == "None" ] || [ -z "${IGW_ID}" ]; then
    log "INFO" "Criando Internet Gateway..."
    IGW_ID=$(${AWSLOCAL} ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJETO}-igw},{Key=Projeto,Value=${PROJETO}},{Key=Proprietario,Value=${PROPRIETARIO}}]" \
        --query "InternetGateway.InternetGatewayId" --output text)
    ${AWSLOCAL} ec2 attach-internet-gateway --vpc-id "${VPC_ID}" --internet-gateway-id "${IGW_ID}"
    log "INFO" "IGW criado e anexado à VPC: ${IGW_ID}"
else
    log "INFO" "IGW já existente, reutilizando: ${IGW_ID}"
fi

#Sub-redes públicas (us-east-1a e us-east-1b)
log "INFO" "Verificando sub-rede pública em ${AZ_A} (${SUB_PUB_A_CIDR})..."
SUBNET_PUB_A_ID=$(buscar_subnet_existente "${VPC_ID}" "${SUB_PUB_A_CIDR}")
if [ -z "${SUBNET_PUB_A_ID}" ]; then
    SUBNET_PUB_A_ID=$(${AWSLOCAL} ec2 create-subnet \
        --vpc-id "${VPC_ID}" --cidr-block "${SUB_PUB_A_CIDR}" --availability-zone "${AZ_A}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJETO}-sub-publica-a},{Key=Projeto,Value=${PROJETO}}]" \
        --query "Subnet.SubnetId" --output text)
    ${AWSLOCAL} ec2 modify-subnet-attribute --subnet-id "${SUBNET_PUB_A_ID}" --map-public-ip-on-launch
    log "INFO" "Sub-rede pública A criada: ${SUBNET_PUB_A_ID} (mapeamento de IP público ativado)"
else
    log "INFO" "Sub-rede pública A já existente, reutilizando: ${SUBNET_PUB_A_ID}"
fi

log "INFO" "Verificando sub-rede pública em ${AZ_B} (${SUB_PUB_B_CIDR})..."
SUBNET_PUB_B_ID=$(buscar_subnet_existente "${VPC_ID}" "${SUB_PUB_B_CIDR}")
if [ -z "${SUBNET_PUB_B_ID}" ]; then
    SUBNET_PUB_B_ID=$(${AWSLOCAL} ec2 create-subnet \
        --vpc-id "${VPC_ID}" --cidr-block "${SUB_PUB_B_CIDR}" --availability-zone "${AZ_B}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJETO}-sub-publica-b},{Key=Projeto,Value=${PROJETO}}]" \
        --query "Subnet.SubnetId" --output text)
    ${AWSLOCAL} ec2 modify-subnet-attribute --subnet-id "${SUBNET_PUB_B_ID}" --map-public-ip-on-launch
    log "INFO" "Sub-rede pública B criada: ${SUBNET_PUB_B_ID} (mapeamento de IP público ativado)"
else
    log "INFO" "Sub-rede pública B já existente, reutilizando: ${SUBNET_PUB_B_ID}"
fi

#Tabela de rotas pública (0.0.0.0/0 -> IGW)
log "INFO" "Verificando tabela de rotas pública..."
RTB_PUB_ID=$(${AWSLOCAL} ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJETO}-rtb-publica" \
    --query "RouteTables[0].RouteTableId" --output text 2>/dev/null | grep -v '^None$' || true)

if [ -z "${RTB_PUB_ID}" ]; then
    RTB_PUB_ID=$(${AWSLOCAL} ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJETO}-rtb-publica},{Key=Projeto,Value=${PROJETO}}]" \
        --query "RouteTable.RouteTableId" --output text)
    ${AWSLOCAL} ec2 create-route --route-table-id "${RTB_PUB_ID}" --destination-cidr-block "0.0.0.0/0" --gateway-id "${IGW_ID}" > /dev/null
    ${AWSLOCAL} ec2 associate-route-table --route-table-id "${RTB_PUB_ID}" --subnet-id "${SUBNET_PUB_A_ID}" > /dev/null
    ${AWSLOCAL} ec2 associate-route-table --route-table-id "${RTB_PUB_ID}" --subnet-id "${SUBNET_PUB_B_ID}" > /dev/null
    log "INFO" "Tabela de rotas pública criada e associada (destino 0.0.0.0/0 -> ${IGW_ID})."
else
    log "INFO" "Tabela de rotas pública já existente, reutilizando: ${RTB_PUB_ID}"
fi

# NAT Gateway (Elastic IP + NAT dentro da sub-rede pública)
log "INFO" "Verificando NAT Gateway..."
NAT_GW_ID=$(${AWSLOCAL} ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=${PROJETO}-natgw" "Name=state,Values=available,pending" \
    --query "NatGateways[0].NatGatewayId" --output text 2>/dev/null | grep -v '^None$' || true)

if [ -z "${NAT_GW_ID}" ]; then
    log "INFO" "Alocando Elastic IP para o NAT Gateway..."
    EIP_ALLOC_ID=$(${AWSLOCAL} ec2 allocate-address --domain vpc --query "AllocationId" --output text)
    log "INFO" "EIP alocado: ${EIP_ALLOC_ID}"

    log "INFO" "Provisionando NAT Gateway na sub-rede pública A..."
    NAT_GW_ID=$(${AWSLOCAL} ec2 create-nat-gateway \
        --subnet-id "${SUBNET_PUB_A_ID}" \
        --allocation-id "${EIP_ALLOC_ID}" \
        --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${PROJETO}-natgw},{Key=Projeto,Value=${PROJETO}}]" \
        --query "NatGateway.NatGatewayId" --output text)
    log "INFO" "NAT Gateway criado: ${NAT_GW_ID}"
else
    log "INFO" "NAT Gateway já existente, reutilizando: ${NAT_GW_ID}"
fi

# -----------------------------------------------------------------------------
# PAUSA 3
# -----------------------------------------------------------------------------
pausa "PAUSA 3: Fundação da Rede Privada"

log "INFO" "Verificando sub-rede privada Web (${AZ_A} - ${SUB_PRIV_WEB_A_CIDR})..."
SUBNET_PRIV_WEB_A_ID=$(buscar_subnet_existente "${VPC_ID}" "${SUB_PRIV_WEB_A_CIDR}")
if [ -z "${SUBNET_PRIV_WEB_A_ID}" ]; then
    SUBNET_PRIV_WEB_A_ID=$(${AWSLOCAL} ec2 create-subnet \
        --vpc-id "${VPC_ID}" --cidr-block "${SUB_PRIV_WEB_A_CIDR}" --availability-zone "${AZ_A}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJETO}-sub-privada-web-a},{Key=Projeto,Value=${PROJETO}}]" \
        --query "Subnet.SubnetId" --output text)
    log "INFO" "Sub-rede privada Web A criada: ${SUBNET_PRIV_WEB_A_ID}"
else
    log "INFO" "Sub-rede privada Web A já existente, reutilizando: ${SUBNET_PRIV_WEB_A_ID}"
fi

log "INFO" "Verificando sub-rede privada Web (${AZ_B} - ${SUB_PRIV_WEB_B_CIDR})..."
SUBNET_PRIV_WEB_B_ID=$(buscar_subnet_existente "${VPC_ID}" "${SUB_PRIV_WEB_B_CIDR}")
if [ -z "${SUBNET_PRIV_WEB_B_ID}" ]; then
    SUBNET_PRIV_WEB_B_ID=$(${AWSLOCAL} ec2 create-subnet \
        --vpc-id "${VPC_ID}" --cidr-block "${SUB_PRIV_WEB_B_CIDR}" --availability-zone "${AZ_B}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJETO}-sub-privada-web-b},{Key=Projeto,Value=${PROJETO}}]" \
        --query "Subnet.SubnetId" --output text)
    log "INFO" "Sub-rede privada Web B criada: ${SUBNET_PRIV_WEB_B_ID}"
else
    log "INFO" "Sub-rede privada Web B já existente, reutilizando: ${SUBNET_PRIV_WEB_B_ID}"
fi

log "INFO" "Verificando sub-rede privada Back-End (${SUB_PRIV_BACKEND_CIDR})..."
SUBNET_PRIV_BACKEND_ID=$(buscar_subnet_existente "${VPC_ID}" "${SUB_PRIV_BACKEND_CIDR}")
if [ -z "${SUBNET_PRIV_BACKEND_ID}" ]; then
    SUBNET_PRIV_BACKEND_ID=$(${AWSLOCAL} ec2 create-subnet \
        --vpc-id "${VPC_ID}" --cidr-block "${SUB_PRIV_BACKEND_CIDR}" --availability-zone "${AZ_A}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJETO}-sub-privada-backend},{Key=Projeto,Value=${PROJETO}}]" \
        --query "Subnet.SubnetId" --output text)
    log "INFO" "Sub-rede privada Back-End criada: ${SUBNET_PRIV_BACKEND_ID}"
else
    log "INFO" "Sub-rede privada Back-End já existente, reutilizando: ${SUBNET_PRIV_BACKEND_ID}"
fi

log "INFO" "Verificando sub-rede privada Database (${SUB_PRIV_DB_CIDR})..."
SUBNET_PRIV_DB_ID=$(buscar_subnet_existente "${VPC_ID}" "${SUB_PRIV_DB_CIDR}")
if [ -z "${SUBNET_PRIV_DB_ID}" ]; then
    SUBNET_PRIV_DB_ID=$(${AWSLOCAL} ec2 create-subnet \
        --vpc-id "${VPC_ID}" --cidr-block "${SUB_PRIV_DB_CIDR}" --availability-zone "${AZ_A}" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJETO}-sub-privada-db},{Key=Projeto,Value=${PROJETO}}]" \
        --query "Subnet.SubnetId" --output text)
    log "INFO" "Sub-rede privada Database criada: ${SUBNET_PRIV_DB_ID}"
else
    log "INFO" "Sub-rede privada Database já existente, reutilizando: ${SUBNET_PRIV_DB_ID}"
fi

#Tabela de rotas privada (0.0.0.0/0 -> NAT Gateway, sem rota p/ IGW)
log "INFO" "Verificando tabela de rotas privada..."
RTB_PRIV_ID=$(${AWSLOCAL} ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${PROJETO}-rtb-privada" \
    --query "RouteTables[0].RouteTableId" --output text 2>/dev/null | grep -v '^None$' || true)

if [ -z "${RTB_PRIV_ID}" ]; then
    RTB_PRIV_ID=$(${AWSLOCAL} ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJETO}-rtb-privada},{Key=Projeto,Value=${PROJETO}}]" \
        --query "RouteTable.RouteTableId" --output text)
    ${AWSLOCAL} ec2 create-route --route-table-id "${RTB_PRIV_ID}" --destination-cidr-block "0.0.0.0/0" --nat-gateway-id "${NAT_GW_ID}" > /dev/null

    for sub in "${SUBNET_PRIV_WEB_A_ID}" "${SUBNET_PRIV_WEB_B_ID}" "${SUBNET_PRIV_BACKEND_ID}" "${SUBNET_PRIV_DB_ID}"; do
        ${AWSLOCAL} ec2 associate-route-table --route-table-id "${RTB_PRIV_ID}" --subnet-id "${sub}" > /dev/null
    done
    log "INFO" "Tabela de rotas privada criada e associada às 4 sub-redes privadas (destino 0.0.0.0/0 -> ${NAT_GW_ID})."
    log "INFO" "Isolamento confirmado: a tabela privada não possui rota para o Internet Gateway."
else
    log "INFO" "Tabela de rotas privada já existente, reutilizando: ${RTB_PRIV_ID}"
fi

# -----------------------------------------------------------------------------
# PAUSA 4:
# -----------------------------------------------------------------------------
pausa "PAUSA 4: Segurança e Acessos (Firewall)"

log "INFO" "Verificando Security Group do Bastion Host (bastionhost-prod-sg)..."
SG_BASTION_ID=$(buscar_sg_existente "${VPC_ID}" "bastionhost-prod-sg")
if [ -z "${SG_BASTION_ID}" ]; then
    SG_BASTION_ID=$(${AWSLOCAL} ec2 create-security-group \
        --group-name "bastionhost-prod-sg" \
        --description "Acesso SSH ao Bastion Host" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Projeto,Value=${PROJETO}}]" \
        --query "GroupId" --output text)
    ${AWSLOCAL} ec2 authorize-security-group-ingress \
        --group-id "${SG_BASTION_ID}" --protocol tcp --port 22 --cidr "0.0.0.0/0" > /dev/null
    log "INFO" "SG Bastion criado: ${SG_BASTION_ID} (porta 22 liberada)"
else
    log "INFO" "SG Bastion já existente, reutilizando: ${SG_BASTION_ID}"
fi

log "INFO" "Verificando Security Group Web (webserver-prod-sg)..."
SG_WEB_ID=$(buscar_sg_existente "${VPC_ID}" "webserver-prod-sg")
if [ -z "${SG_WEB_ID}" ]; then
    SG_WEB_ID=$(${AWSLOCAL} ec2 create-security-group \
        --group-name "webserver-prod-sg" \
        --description "Acesso HTTP/HTTPS via ALB" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Projeto,Value=${PROJETO}}]" \
        --query "GroupId" --output text)
    ${AWSLOCAL} ec2 authorize-security-group-ingress \
        --group-id "${SG_WEB_ID}" --protocol tcp --port 80 --cidr "${VPC_CIDR}" > /dev/null
    ${AWSLOCAL} ec2 authorize-security-group-ingress \
        --group-id "${SG_WEB_ID}" --protocol tcp --port 443 --cidr "${VPC_CIDR}" > /dev/null
    ${AWSLOCAL} ec2 authorize-security-group-ingress \
        --group-id "${SG_WEB_ID}" --protocol tcp --port 22 --source-group "${SG_BASTION_ID}" > /dev/null
    log "INFO" "SG Web criado: ${SG_WEB_ID} (80/443 internos + 22 apenas a partir do Bastion)"
else
    log "INFO" "SG Web já existente, reutilizando: ${SG_WEB_ID}"
fi

log "INFO" "Verificando Security Group Back-End (backend-prod-sg)..."
SG_BACKEND_ID=$(buscar_sg_existente "${VPC_ID}" "backend-prod-sg")
if [ -z "${SG_BACKEND_ID}" ]; then
    SG_BACKEND_ID=$(${AWSLOCAL} ec2 create-security-group \
        --group-name "backend-prod-sg" \
        --description "Trafego apenas do SG Web (encadeamento de seguranca)" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Projeto,Value=${PROJETO}}]" \
        --query "GroupId" --output text)
    ${AWSLOCAL} ec2 authorize-security-group-ingress \
        --group-id "${SG_BACKEND_ID}" --protocol tcp --port 8080 --source-group "${SG_WEB_ID}" > /dev/null
    log "INFO" "SG Back-End criado: ${SG_BACKEND_ID} (porta 8080 liberada apenas do SG Web)"
else
    log "INFO" "SG Back-End já existente, reutilizando: ${SG_BACKEND_ID}"
fi

log "INFO" "Verificando Security Group Database (database-prod-sg)..."
SG_DB_ID=$(buscar_sg_existente "${VPC_ID}" "database-prod-sg")
if [ -z "${SG_DB_ID}" ]; then
    SG_DB_ID=$(${AWSLOCAL} ec2 create-security-group \
        --group-name "database-prod-sg" \
        --description "Trafego apenas do SG Backend" \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Projeto,Value=${PROJETO}}]" \
        --query "GroupId" --output text)
    ${AWSLOCAL} ec2 authorize-security-group-ingress \
        --group-id "${SG_DB_ID}" --protocol tcp --port 3306 --source-group "${SG_BACKEND_ID}" > /dev/null
    log "INFO" "SG Database criado: ${SG_DB_ID} (porta 3306 liberada apenas do SG Backend; sem banco provisionado nesta Sprint - ver observação no fim do script)"
else
    log "INFO" "SG Database já existente, reutilizando: ${SG_DB_ID}"
fi

# -----------------------------------------------------------------------------
# PAUSA 5
# -----------------------------------------------------------------------------
pausa "PAUSA 5: Computação, Dados e Validação do Deploy"

#AMI fixa (evita que mudanças externas quebrem o provisionamento)
log "INFO" "Buscando uma AMI disponível no LocalStack..."
AMI_ID=$(${AWSLOCAL} ec2 describe-images --query "Images[0].ImageId" --output text 2>/dev/null || echo "ami-000000000")
[ "${AMI_ID}" == "None" ] && AMI_ID="ami-000000000"
log "INFO" "AMI utilizada: ${AMI_ID}"

log "INFO" "Lançando instância do Bastion Host na sub-rede pública A..."
INSTANCE_BASTION_ID=$(${AWSLOCAL} ec2 run-instances \
    --image-id "${AMI_ID}" --count 1 --instance-type t2.micro \
    --subnet-id "${SUBNET_PUB_A_ID}" --security-group-ids "${SG_BASTION_ID}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJETO}-bastion-host},{Key=Projeto,Value=${PROJETO}},{Key=Proprietario,Value=${PROPRIETARIO}}]" \
    --query "Instances[0].InstanceId" --output text)
log "INFO" "Bastion Host lançado: ${INSTANCE_BASTION_ID}"

log "INFO" "Lançando instâncias Web na sub-rede privada Web A e B..."
INSTANCE_WEB_A_ID=$(${AWSLOCAL} ec2 run-instances \
    --image-id "${AMI_ID}" --count 1 --instance-type t2.micro \
    --subnet-id "${SUBNET_PRIV_WEB_A_ID}" --security-group-ids "${SG_WEB_ID}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJETO}-web-a},{Key=Projeto,Value=${PROJETO}},{Key=Proprietario,Value=${PROPRIETARIO}}]" \
    --query "Instances[0].InstanceId" --output text)
INSTANCE_WEB_B_ID=$(${AWSLOCAL} ec2 run-instances \
    --image-id "${AMI_ID}" --count 1 --instance-type t2.micro \
    --subnet-id "${SUBNET_PRIV_WEB_B_ID}" --security-group-ids "${SG_WEB_ID}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJETO}-web-b},{Key=Projeto,Value=${PROJETO}},{Key=Proprietario,Value=${PROPRIETARIO}}]" \
    --query "Instances[0].InstanceId" --output text)
log "INFO" "Instâncias Web lançadas: ${INSTANCE_WEB_A_ID} / ${INSTANCE_WEB_B_ID} (sem IP público)"

log "INFO" "Lançando instância Back-End na sub-rede privada Back-End..."
INSTANCE_BACKEND_ID=$(${AWSLOCAL} ec2 run-instances \
    --image-id "${AMI_ID}" --count 1 --instance-type t2.micro \
    --subnet-id "${SUBNET_PRIV_BACKEND_ID}" --security-group-ids "${SG_BACKEND_ID}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJETO}-backend},{Key=Projeto,Value=${PROJETO}},{Key=Proprietario,Value=${PROPRIETARIO}}]" \
    --query "Instances[0].InstanceId" --output text)
log "INFO" "Instância Back-End lançada: ${INSTANCE_BACKEND_ID}"

#Buckets S3 conforme a arquitetura (Raw, Trusted, Curated, Histórico)
log "INFO" "Verificando buckets S3 da camada de dados..."
for bucket in "raw" "trusted" "curated" "historico"; do
    NOME_BUCKET="${PROJETO}-bucket-${bucket}"
    if ${AWSLOCAL} s3api head-bucket --bucket "${NOME_BUCKET}" > /dev/null 2>&1; then
        log "INFO" "Bucket já existente, reutilizando: ${NOME_BUCKET}"
    else
        ${AWSLOCAL} s3 mb "s3://${NOME_BUCKET}" > /dev/null
        log "INFO" "Bucket criado: ${NOME_BUCKET}"
    fi
done




# -----------------------------------------------------------------------------
# VALIDAÇÃO FINAL
# -----------------------------------------------------------------------------
pausa "VALIDAÇÃO FINAL"

log "INFO" "Testando conectividade de saída do NAT (describe do NAT Gateway)..."
${AWSLOCAL} ec2 describe-nat-gateways --nat-gateway-ids "${NAT_GW_ID}" \
    --query "NatGateways[0].State" --output text | tee -a "${LOG_FILE}"

echo ""
log "INFO" "===================== RESUMO DOS RECURSOS CRIADOS ====================="
log "INFO" "VPC:                 ${VPC_ID}"
log "INFO" "Internet Gateway:    ${IGW_ID}"
log "INFO" "NAT Gateway:         ${NAT_GW_ID}"
log "INFO" "Sub-rede Pub A:      ${SUBNET_PUB_A_ID}"
log "INFO" "Sub-rede Pub B:      ${SUBNET_PUB_B_ID}"
log "INFO" "Sub-rede Priv Web A: ${SUBNET_PRIV_WEB_A_ID}"
log "INFO" "Sub-rede Priv Web B: ${SUBNET_PRIV_WEB_B_ID}"
log "INFO" "Sub-rede Backend:    ${SUBNET_PRIV_BACKEND_ID}"
log "INFO" "Sub-rede Database:   ${SUBNET_PRIV_DB_ID}"
log "INFO" "SG Bastion:          ${SG_BASTION_ID}"
log "INFO" "SG Web:              ${SG_WEB_ID}"
log "INFO" "SG Backend:          ${SG_BACKEND_ID}"
log "INFO" "SG Database:         ${SG_DB_ID}"
log "INFO" "Instância Bastion:   ${INSTANCE_BASTION_ID}"
log "INFO" "Instâncias Web:      ${INSTANCE_WEB_A_ID}, ${INSTANCE_WEB_B_ID}"
log "INFO" "Instância Backend:   ${INSTANCE_BACKEND_ID}"
log "INFO" "SG Database:         ${SG_DB_ID} (pronto p/ receber banco)"
log "INFO" "Log completo salvo em: ${LOG_FILE}"
log "INFO" "===================================================================================================================="
log "INFO" "OBS: RDS/EFS não foram provisionados nesta simulação: LocalStack Community não suporta esses serviços gratuitamente."
log "INFO" "===================================================================================================================="

echo ""
log "INFO" "Simulação da infraestrutura concluída com sucesso."