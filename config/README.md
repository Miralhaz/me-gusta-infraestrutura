# MeGusta - Configuração Docker Swarm

> **Documento operacional.** Siga as etapas **exatamente na ordem**.
> Comandos marcados com `# LOCAL` rodam no **seu computador**; os demais rodam
> nos nós EC2 (bastion-a / bastion-b / workers).

---

## 📁 Estrutura

```
config/
├── README.md                    # Este arquivo
├── deploy-swarm.sh             # Script principal de deploy (executa no bastion-a)
├── join-swarm.sh               # Script para juntar nós ao Swarm (executa em cada nó)
├── label-nodes.sh              # Script para labelar nós (executa no bastion-a)
├── build-images.sh             # Build standalone (opcional, para CI/CD)
├── .env.example                # Modelo das variáveis do consumer (SES/SMTP)
├── patches/
│   └── consumer-email.patch    # Patch transitório do consumer (WhatsApp → e-mail)
├── docker/
│   ├── docker-compose.yml      # Stack principal do Swarm
│   ├── Dockerfile.database     # Imagem customizada MySQL (repo do banco NÃO tem Dockerfile)
│   ├── frontend.Dockerfile     # Dockerfile do frontend (copiado para a subpasta do repo)
│   ├── backend.Dockerfile      # Dockerfile do backend  (copiado para a subpasta do repo)
│   ├── consumer.Dockerfile     # Dockerfile do consumer (copiado para a subpasta do repo)
│   ├── nginx.conf              # SPA + reverse proxy /api -> backend:8080 (copiado p/ frontend)
│   ├── config/
│   │   └── mysql/
│   │       └── custom.cnf      # Configuração MySQL otimizada
│   ├── rabbitmq/
│   │   ├── Dockerfile          # Imagem customizada RabbitMQ (config embutida)
│   │   └── rabbitmq.conf       # Configuração RabbitMQ (sem load_definitions)
│   ├── init-scripts/
│   │   ├── 01-schema.sql       # Schema do banco
│   │   └── 02-seed-data.sql    # Dados iniciais
│   └── scripts/
│       └── healthcheck.sh      # Healthcheck customizado do MySQL
```

---

## 🏗️ Arquitetura do Swarm

| Nó | Hostname (Terraform) | Role | AZ | Serviços |
|----|----------------------|------|-----|----------|
| **bastion-host-a** | megusta-prod-us1-bastion-host-a | Manager Leader | az-a | registry local (porta 5000) + build |
| **bastion-host-b** | megusta-prod-us1-bastion-host-b | Manager | az-b | — |
| **web-a** | megusta-prod-us1-web-a | Worker | az-a | frontend (1 replica, host port 8080) |
| **web-b** | megusta-prod-us1-web-b | Worker | az-b | frontend (1 replica, host port 8080) |
| **backend-a** | megusta-prod-us1-backend-a | Worker | az-a | backend (1 replica) + consumer (1 replica) |
| **backend-b** | megusta-prod-us1-backend-b | Worker | az-b | backend (1 replica) + consumer (1 replica) |
| **database-a** | megusta-prod-us1-database-a | Worker | az-a | database (1 replica) |

- **Rede:** 1 NAT Gateway gerenciado (AZ A); route tables privadas (AZ A + AZ B) apontam `0.0.0.0/0` para ele.
- **7 instâncias EC2:** 2 managers + 5 workers. Os bastions ficam em subnets públicas (com Elastic IP); os 5 workers ficam em subnets privadas (**sem IP público**).

---

## ✅ Pré-requisitos (antes de qualquer coisa)

- [ ] `tofu apply` concluído (rodado **na sua máquina**, a partir do `terraform.tfvars`). 7 instâncias + NAT Gateway + ALB. A identidade do SES só é criada com `enable_ses_email_identity = true`; no AWS Academy ela fica desligada e o e-mail usa SMTP.
- [ ] Credenciais AWS válidas no seu computador (`aws sts get-caller-identity`) para o `tofu apply`.
- [ ] Chave SSH privada em `Terraform-full/megusta-key`.
- [ ] Buckets S3 criados manualmente: `megusta-raw-us-east-1`, `megusta-trusted-us-east-1`, `megusta-curated-us-east-1`.
- [ ] Repositórios do GitHub acessíveis (públicos): `Miralhaz/me-gusta-frontend`, `Miralhaz/me-gusta-backend`, `Miralhaz/me-gusta-database`, `Miralhaz/me-gusta-microsservico`.

### ⚠️ Sobre a recriação das instâncias (leia!)

O `user_data` **só roda no primeiro boot**. Qualquer mudança em `user_data` (ou no
`instance_type` / disco) faz o `tofu apply` **recriar** a instância.

- O apply mais recente **recria os 2 bastions** — que agora são **`t3.medium` (4 GB)**,
  com **30 GB de disco** e com **`docker-compose` instalado automaticamente** no
  `user_data` (o `deploy-swarm.sh` exige o comando `docker-compose`/`docker compose`
  no pré-requisito).
- Os outros 5 nós **não mudam** se o `user_data` deles não mudou.
- Como os bastions são recriados, **pegue o IP público atualizado** deles (ver abaixo)
  e **reenvie** a pasta `config/` + a chave para o bastion-a (ETAPA 1).

> 💡 O bastion-a é o manager leader, roda o registry na porta 5000 e é quem faz o
> **build das 5 imagens**. Por isso ele é `t3.medium` com 30 GB. Se fizer muitos
> `--rebuild`, rode `docker system prune -af` para liberar espaço.

---

## 🔑 Como acessar os nós (SSH)

- **Somente os bastions têm IP público** (Elastic IP). Você entra por eles.
- Os **workers estão em subnets privadas** (`map_public_ip_on_launch = false`) e o
  SSH deles é liberado **apenas a partir do Security Group do bastion**. Ou seja:
  para chegar em um worker, você passa **pelo bastion-a**.

**LOCAL — descubra os IPs (outputs do Terraform):**
```bash
cd <caminho>/me-gusta-infraestrutura

tofu -chdir=Terraform-full output -raw bastion_host_a_public_ip
tofu -chdir=Terraform-full output -raw bastion_host_b_public_ip
tofu -chdir=Terraform-full output -raw alb_dns_name

# IPs privados (usados para o join a partir do bastion-a):
tofu -chdir=Terraform-full output -raw web_server_a_private_ip
tofu -chdir=Terraform-full output -raw web_server_b_private_ip
tofu -chdir=Terraform-full output -raw backend_a_private_ip
tofu -chdir=Terraform-full output -raw backend_b_private_ip
tofu -chdir=Terraform-full output -raw database_a_private_ip
# (IP privado do bastion-b: pegue no console EC2 -> Instances -> Private IPv4)
```

---

## ETAPA 1 — Enviar `config/` + chave para o bastion-a

**LOCAL** (no seu computador, na raiz do repositório):
```bash
BASTION_A_IP=$(tofu -chdir=Terraform-full output -raw bastion_host_a_public_ip)

# envia a chave privada (para o bastion-a conseguir acessar os workers)...
scp -i Terraform-full/megusta-key Terraform-full/megusta-key ubuntu@${BASTION_A_IP}:/home/ubuntu/

# ...e a pasta config/
scp -r -i Terraform-full/megusta-key config ubuntu@${BASTION_A_IP}:/home/ubuntu/

# entra no bastion-a
ssh -i Terraform-full/megusta-key ubuntu@${BASTION_A_IP}
```

> ❗ **A opção de "clonar o repositório de infraestrutura do GitHub" NÃO funciona**:
> a pasta `config/` e o `Terraform-full/` não estão versionados no GitHub. O caminho
> é sempre o `scp` acima.

---

## ETAPA 2 — Deploy principal (no bastion-a) 🎯

No bastion-a, como root, na pasta `config`:

```bash
sudo su -
cd /home/ubuntu/config
chmod +x *.sh
./deploy-swarm.sh --rebuild --sync-github
```

**O que o script faz automaticamente:**
1. ✅ Verifica pré-requisitos (Docker, **Docker Compose**, arquivo compose).
2. ✅ Inicializa o Swarm no bastion-a (manager leader).
3. ✅ Sobe o **Local Registry** na porta 5000 (dados em `/opt/megusta/registry`).
4. ✅ Configura `insecure-registries` no Docker do bastion-a.
5. ✅ Clona os 4 repositórios do GitHub em `/opt/megusta/src/`.
6. ✅ Aplica o patch transitório `patches/consumer-email.patch` no consumer
   (só enquanto o repo ainda tiver `WhatsAppService.java`; ver seção 10). Quando
   aplica, a imagem do consumer é **rebuildada mesmo sem `--rebuild`**.
7. ✅ Copia os Dockerfiles/assets da infra para dentro dos repos clonados —
   o código **não** está na raiz dos repos:
   - frontend → `me-gusta-frontend/me-gusta-frontend` (recebe `Dockerfile` + `nginx.conf`)
   - backend → `me-gusta-backend/megusta` (recebe `Dockerfile`)
   - database → raiz de `me-gusta-database` (recebe `Dockerfile` + assets)
   - consumer → `me-gusta-microsservico/megusta-consumer/megusta-consumer` (recebe `Dockerfile`)
8. ✅ Faz **build das 5 imagens + push** para o registry:
   - `<MANAGER_IP>:5000/megusta-frontend:latest`
   - `<MANAGER_IP>:5000/megusta-backend:latest`
   - `<MANAGER_IP>:5000/megusta-database:latest`
   - `<MANAGER_IP>:5000/megusta-rabbitmq:latest`
   - `<MANAGER_IP>:5000/megusta-consumer:latest`
9. ✅ Faz `docker stack deploy` do stack `megusta`.

> ⚠️ **Antes do deploy**, crie o `config/.env` com as variáveis do consumer
> (veja [Consumer de alertas por e-mail](#-consumer-de-alertas-por-e-mail)).
> No AWS Academy use `MAIL_TRANSPORT=smtp` (padrão do `.env.example`): são
> exigidos `SMTP_HOST`/`SMTP_FROM` e, quando `SMTP_AUTH=true`,
> `SMTP_USERNAME`/`SMTP_PASSWORD`. O transporte `ses` é opcional e só funciona
> em uma conta cuja role permita criar/verificar a identidade. O script valida
> conforme o transporte e aborta com mensagem clara se faltar algo.

> As URLs do GitHub já apontam para a org `Miralhaz` (topo do `deploy-swarm.sh`).
> Só altere se seus repos estiverem em outra conta.

### 📌 ANOTE os 4 valores que o script imprime (vão ser usados na ETAPA 3):
```
Manager Token:        SWMTKN-1-xxxxxxxxxxxxxxxxxxxx
Worker Token:         SWMTKN-1-yyyyyyyyyyyyyyyyyyyy
Manager IP (privado): 10.0.0.xxx
Registry URL:         http://10.0.0.xxx:5000
```

> ⚠️ **É NORMAL os serviços ficarem `Pending` (0/N) agora.** Como os workers ainda
> não entraram no Swarm nem têm labels, o `placement.constraints` não encontra
> destino. Depois das ETAPAS 3 e 4 (join + labels), o Swarm agenda tudo sozinho.
> Não se preocupe com o aviso de timeout no fim do script.

---

## ETAPA 3 — Juntar os nós (a partir do bastion-a)

Todos os comandos abaixo são rodados **no bastion-a** (ele já tem a chave e o
`join-swarm.sh`). Defina as variáveis uma vez:

```bash
KEY=/home/ubuntu/megusta-key
JOIN=/home/ubuntu/config/join-swarm.sh
MGR_IP="<IP_PRIVADO_BASTION_A>"
MGR_TOKEN="<MANAGER_TOKEN>"
WRK_TOKEN="<WORKER_TOKEN>"
```

Para **cada nó**, copie o `join-swarm.sh` e execute o join:

**bastion-b (como manager):**
```bash
scp -i $KEY $JOIN ubuntu@<IP_PRIVADO_BASTION_B>:/home/ubuntu/
ssh -i $KEY ubuntu@<IP_PRIVADO_BASTION_B> "sudo bash /home/ubuntu/join-swarm.sh $MGR_IP $MGR_TOKEN manager"
```

**cada worker (como worker):** repita para `web-a`, `web-b`, `backend-a`,
`backend-b`, `database-a` (use o IP privado correspondente):
```bash
scp -i $KEY $JOIN ubuntu@<IP_PRIVADO_DO_WORKER>:/home/ubuntu/
ssh -i $KEY ubuntu@<IP_PRIVADO_DO_WORKER> "sudo bash /home/ubuntu/join-swarm.sh $MGR_IP $WRK_TOKEN worker"
```

> O `join-swarm.sh` **configura automaticamente** o `insecure-registries` no
> `daemon.json` e reinicia o Docker antes de juntar ao Swarm — não faça nada manual.

**Verifique do bastion-a:**
```bash
docker node ls
# Devem aparecer os 7 nós: bastion-host-a (Leader), bastion-host-b (Reachable),
# + web-a, web-b, backend-a, backend-b, database-a (Ready/Active)
```

> Alternativa (LOCAL, sem copiar a chave para o bastion): use ProxyJump —
> `ssh -i Terraform-full/megusta-key -J ubuntu@${BASTION_A_IP} ubuntu@<IP_PRIVADO_DO_WORKER>`.

---

## ETAPA 4 — Labelar os nós (no bastion-a)

```bash
cd /home/ubuntu/config
./label-nodes.sh
```

**Verifique:**
```bash
docker node ls --format "table {{.Hostname}}\t{{.ManagerStatus}}\t{{.Labels}}"
```

Deve resultar em:

| Hostname | Labels |
|----------|--------|
| megusta-prod-us1-bastion-host-a | az=az-a, role=manager |
| megusta-prod-us1-bastion-host-b | az=az-b, role=manager |
| megusta-prod-us1-web-a | az=az-a, role=web |
| megusta-prod-us1-web-b | az=az-b, role=web |
| megusta-prod-us1-backend-a | az=az-a, role=backend |
| megusta-prod-us1-backend-b | az=az-b, role=backend |
| megusta-prod-us1-database-a | az=az-a, role=database |

> Os hostnames são **exatamente** os definidos nas tags `Name` do Terraform. Se o
> `label-nodes.sh` avisar "nó não encontrado", o hostname do nó não bate — recrie a
> instância (o `user_data` define o hostname no boot).

Com as labels aplicadas, o Swarm começa a agendar as tasks (que estavam `Pending`).
Aguarde 1–2 minutos.

---

## ETAPA 5 — Verificar o deploy

```bash
docker stack services megusta
docker stack ps megusta
```

**Esperado:**

| Serviço | Replicas | Onde |
|---------|----------|------|
| megusta_frontend | 2/2 | web-a (az-a), web-b (az-b) |
| megusta_backend  | 2/2 | backend-a (az-a), backend-b (az-b) |
| megusta_consumer | 2/2 | backend-a (az-a), backend-b (az-b) |
| megusta_database | 1/1 | database-a (az-a) |
| megusta_rabbitmq | 1/1 | um worker (broker único; ver nota 4) |

**Testes de saúde (a partir do bastion-a):**
```bash
docker run -it --rm --network megusta-net curlimages/curl curl -s http://frontend/health
docker run -it --rm --network megusta-net curlimages/curl curl -s http://backend:8080/v3/api-docs
docker run -it --rm --network megusta-net curlimages/curl curl -s http://frontend/api/insumos
```

**Consumer (worker, sem porta HTTP):**
```bash
docker service logs megusta_consumer --tail 50
# Esperado: conexão AMQP estabelecida, listener em megusta.email.alertas e,
# no primeiro alerta, "Alerta de estoque enviado por e-mail para <destino>"
```

---

## ETAPA 6 — Acesso à aplicação (produção)

**LOCAL:**
```bash
ALB_DNS=$(tofu -chdir=Terraform-full output -raw alb_dns_name)
echo "http://${ALB_DNS}"
```

Abra `http://${ALB_DNS}` no navegador. O ALB faz health check em `/health` nas
instâncias **web-a** e **web-b** — ambos os targets devem ficar `healthy`.

---

## 📧 Consumer de alertas por e-mail

O consumer é um **serviço separado** (`megusta_consumer`), não faz parte da imagem
do RabbitMQ. Ele roda como worker Java 21 / Spring Boot, sem porta HTTP e sem
acesso ao MySQL:

```text
backend (publisher)
  └─ exchange "megusta.estoque" / routing key "alerta.estoque"
       └─ fila "megusta.email.alertas" (declarada pelo consumer)
            └─ consumer ─┬─ MAIL_TRANSPORT=smtp → servidor SMTP (TLS)  [padrão no Academy]
                         └─ MAIL_TRANSPORT=ses  → AWS SES v2 (API)    [opcional]
                                   │
                                   └─ caixa de e-mail do destinatário
```

O consumer também declara uma DLQ (`megusta.email.alertas.dlq`) e usa até 3
tentativas antes de encaminhar a mensagem para ela.

| Transporte | Credencial | Quando usar |
|---|---|---|
| `smtp` (**padrão no AWS Academy**) | `SMTP_USERNAME` / `SMTP_PASSWORD` no `config/.env` | Gmail, Microsoft 365 ou outro SMTP. Preserva o destinatário do campo `email` da mensagem. |
| `ses` (opcional) | `LabInstanceProfile` da instância (temporária, sem senha) | Só em conta cuja role permita `ses:CreateEmailIdentity`, `ses:GetEmailIdentity` e `ses:SendEmail`. No AWS Academy atual essas ações são bloqueadas. |

### 1. Amazon SES (opcional)

> **AWS Academy:** a role `voclabs` e o `LabRole` das instâncias negam
> `ses:CreateEmailIdentity`, `ses:VerifyEmailIdentity`, `ses:GetAccount`,
> `ses:ListEmailIdentities` e até `ses:SendEmail`. Por isso a identidade SES fica
> **desligada por padrão** (`enable_ses_email_identity = false`) e o transporte
> padrão do `.env.example` é `smtp`. As instruções abaixo servem para uma conta
> com permissão; no lab, pule para a configuração SMTP na seção 2.

#### 1.1 Verificar a identidade do remetente

O Terraform gerencia as identidades em `Terraform-full/ses.tf`, a partir de
`var.ses_email_identities` (padrão: `henry.silva@sptech.school`), **somente
quando** `enable_ses_email_identity = true` no `terraform.tfvars`.

**LOCAL** (na raiz do repositório, com credenciais AWS válidas):

```bash
tofu -chdir=Terraform-full apply
```

Com a flag habilitada, o apply **cria a identidade e a AWS envia um e-mail de
verificação** para o endereço. Enquanto o link não for clicado, o SES rejeita o
envio com `MessageRejected: Email address is not verified`.

> Se a identidade já existir (criada à mão no console), importe antes de aplicar:
> ```bash
> tofu -chdir=Terraform-full import \
>   'aws_sesv2_email_identity.alertas["henry.silva@sptech.school"]' \
>   henry.silva@sptech.school
> ```
>
> Se o apply falhar com `AccessDenied` ao criar a identidade, a role da conta
> não permite SES. No AWS Academy isso é esperado (inclusive no console): use
> `MAIL_TRANSPORT=smtp` e siga a seção 2.

1. Abra a caixa do endereço configurado (ex.: `henry.silva@sptech.school`).
2. Clique em **Verify this email address** (confira o spam; o link expira em 24 h).
3. Confirme a verificação:

```bash
aws sesv2 get-email-identity \
  --email-identity henry.silva@sptech.school --region us-east-1

# alternativa (SES v1):
aws ses get-identity-verification-attributes \
  --identities henry.silva@sptech.school --region us-east-1

# e o output do Terraform:
tofu -chdir=Terraform-full output ses_email_identity_verified_for_sending
```

O esperado é `"VerificationStatus": "Success"` (v1) e
`verified_for_sending_status = true` (Terraform).

> Se o e-mail não chegar, reenvie com
> `aws ses verify-email-identity --email-address henry.silva@sptech.school --region us-east-1`.

#### 1.2 Sandbox do SES

Contas novas do SES começam em **sandbox**: só é possível enviar **de** e **para**
identidades verificadas (limite de 200 e-mails/dia).

- O remetente (`SES_FROM`) **sempre** precisa estar verificado.
- No teste, o **mesmo endereço** é remetente e destinatário — uma identidade
  cobre os dois papéis.
- Para enviar para outra caixa (ex.: um Gmail), verifique também esse endereço:
  inclua em `ses_email_identities` no `terraform.tfvars` e rode `tofu apply`.
- Para produção, solicite a saída do sandbox no console (SES → Account dashboard
  → **Request production access**).

```bash
# mostra se o envio está habilitado e se a conta ainda está em sandbox
aws sesv2 get-account --region us-east-1
```

#### 1.3 Permissões e rede (o que o Terraform já faz)

- **backend-a** e **backend-b** usam o `LabInstanceProfile`
  (`var.lab_instance_profile_name`); no AWS Academy esse perfil carrega a
  `LabRole`, que permite chamar o SES.
- `metadata_options` com `http_put_response_hop_limit = 2` nas duas instâncias
  backend (`Terraform-full/computacao.tf`). O consumer roda **em container** e,
  com o hop limit padrão (`1`), só o host alcançaria o IMDS
  (`169.254.169.254`). Sem isso o SDK não obtém credenciais e falha com
  `Unable to load credentials from any of the providers`.
- Nenhum Security Group novo: o consumer fala com o RabbitMQ pela rede overlay
  `megusta-net` e com o SES pela saída liberada (egress all) via NAT Gateway.

> ⚠️ **AWS Academy:** criar usuário IAM costuma ser bloqueado. Por isso o padrão é
> a **API do SES com o instance profile**, e não SES SMTP (que exigiria
> credenciais SMTP de um usuário IAM).

> ℹ️ Essa mudança é aplicada pelo `tofu apply` como ajuste de metadata da
> instância (o `user_data` não é reexecutado). Depois do apply, force o serviço
> para que as tasks do consumer peguem as credenciais:
> `docker service update --force megusta_consumer`.

### 2. Configurar as variáveis (no bastion-a)

```bash
cd /home/ubuntu/config
cp .env.example .env
chmod 600 .env
nano .env
```

Com `MAIL_TRANSPORT=smtp` (padrão no AWS Academy):

| Variável | Obrigatória | Descrição |
|---|---|---|
| `SMTP_HOST` | Sim | Host do servidor SMTP (ex.: `smtp.gmail.com`). |
| `SMTP_PORT` | Não | Porta SMTP (padrão `587` com STARTTLS; `465` com `SMTP_SSL=true`). |
| `SMTP_USERNAME` | Sim¹ | Usuário da conta que **envia**. |
| `SMTP_PASSWORD` | Sim¹ | Senha do SMTP. No Gmail é **senha de app**, não a senha normal. |
| `SMTP_FROM` | Sim | Remetente exibido no e-mail (normalmente igual ao `SMTP_USERNAME`). |
| `SMTP_AUTH` | Não | `true` (padrão) autentica no SMTP. |
| `SMTP_STARTTLS` | Não | `true` (padrão) usa STARTTLS na porta 587. |
| `SMTP_SSL` | Não | `true` só para porta 465 (SSL direto). Padrão `false`. |

¹ Obrigatória apenas quando `SMTP_AUTH=true`.

Com `MAIL_TRANSPORT=ses` (opcional, só em conta com permissão):

| Variável | Obrigatória | Descrição |
|---|---|---|
| `SES_FROM` | Sim | Remetente **verificado no SES** (ex.: `henry.silva@sptech.school`). |
| `SES_REGION` | Não | Região do SES (padrão `us-east-1`). Precisa ser a mesma onde a identidade foi verificada. |
| `ALERTA_EMAIL_TO` | Não | Destinatário fixo de teste; **deixe vazio em produção**. |

> O `deploy-swarm.sh` carrega `config/.env` automaticamente, exporta as variáveis
> para o `docker stack deploy` e valida o que é obrigatório **conforme o
> transporte escolhido** (aborta antes do build com mensagem clara).
> O `.env` está no `.gitignore` e fica com permissão `600`.

> **Remetente (`MEGUSTA_EMAIL_FROM`).** O container recebe o remetente já
> resolvido pelo `deploy-swarm.sh`: `MEGUSTA_EMAIL_FROM` (se definido) →
> `SES_FROM` → `SMTP_FROM`. A resolução fica no bash porque o Docker Compose
> **não suporta interpolação aninhada** (`${A:-${B:-}}` vira string literal).
> Na prática, com `MAIL_TRANSPORT=smtp` basta preencher `SMTP_FROM`; não é
> preciso definir `MEGUSTA_EMAIL_FROM`.

> Em produção o ideal é migrar `SMTP_PASSWORD` (se usar SMTP) para Docker Secrets
> ou AWS Secrets Manager; hoje ele entra como variável de ambiente (visível em
> `docker service inspect`). No transporte `ses` **não existe senha de e-mail**
> no stack.

> Se a senha tiver `$`, `#` ou espaço, coloque entre aspas simples no `.env`:
> `SMTP_PASSWORD='abcd efgh ijkl mnop'`.

### 3. De onde vem o remetente

O destinatário é dado do banco; o **remetente** é configuração de infraestrutura.

| Provedor | Remetente | O que precisa |
|---|---|---|
| **Gmail** — recomendado no Academy | `SMTP_FROM` | Verificação em duas etapas + **Senha de app**. A senha normal não funciona. |
| **Microsoft 365** | `SMTP_FROM` | SMTP AUTH habilitado no tenant; com MFA, usar app password. |
| **Amazon SES (SMTP)** | `SMTP_FROM` | Credenciais SMTP do IAM + identidade verificada. Exige usuário IAM (normalmente bloqueado no Academy). |
| **Amazon SES (API)** — opcional | `SES_FROM` | Identidade verificada no SES (`enable_ses_email_identity = true` + clique no link). Credenciais vêm do `LabInstanceProfile`. |

> A conta `@sptech.school` pode ter SMTP bloqueado pelo administrador do
> Workspace. Nesse caso, use uma conta Gmail pessoal como **remetente**
> (`SMTP_USERNAME`/`SMTP_FROM`) e mantenha `ALERTA_EMAIL_TO=henry.silva@sptech.school`
> para o alerta chegar na caixa da faculdade.

### 4. Destinatário do alerta (teste e produção)

O destino normal vem no campo `email` da mensagem publicada pelo backend
(`AlertaEstoqueMensagem`), preenchido com `usuario.email` do **último usuário
cadastrado** (`findTopByOrderByIdDesc`). Não há migração de schema: a coluna
`usuario.email` já existe.

Para testar sem mexer no banco, use `ALERTA_EMAIL_TO` no `config/.env`:

```dotenv
ALERTA_EMAIL_TO=henry.silva@sptech.school
```

Com essa variável preenchida, **todo** alerta vai para ela, ignorando o e-mail
da mensagem. Para voltar ao fluxo real, deixe `ALERTA_EMAIL_TO=` vazio e
atualize o usuário mais recente:

```sql
UPDATE usuario SET email = 'henry.silva@sptech.school' WHERE id = (SELECT MAX(id) FROM (SELECT id FROM usuario) t);
```

> Para trocar o destinatário de teste com segurança, altere **só** a linha
> `ALERTA_EMAIL_TO` no `config/.env` (fora do Git) e rode o deploy de novo. Nada
> de e-mail fica hardcoded no compose.

> No sandbox do SES o destinatário também precisa estar verificado (seção 1.2).

### 5. Fazer o deploy

```bash
./deploy-swarm.sh --rebuild --sync-github
```

### 6. Validar

```bash
docker stack services megusta | grep consumer
docker service logs megusta_consumer --tail 50 -f
```

O que deve aparecer:

- conexão AMQP com `rabbitmq:5672`;
- listener na fila `megusta.email.alertas`;
- nenhuma exceção de `SES_*`/`SMTP_*`, `MailSendException`, `MessageRejected` ou
  de autenticação no broker.

**Teste de envio direto pelo SES (LOCAL, sem passar pelo consumer):**

```bash
aws sesv2 send-email --region us-east-1 \
  --from-email-address henry.silva@sptech.school \
  --destination ToAddresses=henry.silva@sptech.school \
  --content "Simple={Subject={Data=\"Teste MeGusta\",Charset=UTF-8},Body={Text={Data=\"Teste de envio SES\",Charset=UTF-8}}}"
```

Se esse comando funcionar, o problema (se houver) está no stack, não no SES.
Erros comuns: `MessageRejected` (identidade não verificada / destinatário fora do
sandbox) e `AccessDenied` (role da instância sem permissão de SES).

### 7. Testar o fluxo

1. Confirme a fila/binding na UI do RabbitMQ (`admin` / `admin`, porta 15672,
   acessível pela rede interna).
2. Dispare o fluxo de estoque abaixo do mínimo no backend **ou** publique um
   JSON no exchange: `{"email":"henry.silva@sptech.school","alertas":[{"nome":"Farinha","codigoInsumo":"INS001","qtdAtual":2.0,"estoqueMinimo":5.0}]}`
   em **Exchanges → megusta.estoque → Publish message**, *Routing key*
   `alerta.estoque`, *Content type* `application/json`.
3. Acompanhe `docker service logs megusta_consumer -f` e verifique o e-mail na
   caixa de destino (confira também o spam no primeiro envio).

> O backend publica somente para o usuário mais recente, no horário definido
> pelo cron `0 0 7 * * *` do `VerificacaoEstoqueScheduler` (**código do
> backend**, não do compose). O container não define `TZ`, então o fuso efetivo
> é **UTC** (≈ 04:00 em Brasília). Para disparar às 07:00 de Brasília é preciso
> ajustar o backend (cron ou `TZ`) — não há variável no stack para isso hoje.
> A publicação só acontece quando existe ao menos um insumo ativo com
> `qtd_atual < estoque_minimo`. Se nenhum item estiver abaixo do mínimo, nada é
> publicado e o consumer não envia nada.
>
> A publicação manual no exchange é a exceção: ela ignora o filtro de estoque e
> envia exatamente o que estiver no JSON — use só para teste. O consumer também
> não revalida o mínimo, ele confia no producer.

### 8. Escalar

O serviço já sobe com `replicas: 2`. Como os dois consumers compartilham a
**mesma fila**, o RabbitMQ faz round-robin e cada mensagem vai para apenas um
deles. Para aumentar a vazão, basta subir `replicas` no compose (respeitando o
limite de nós com `node.labels.role == backend`).

### 9. O que muda no código (backend e consumer)

**Backend (`me-gusta-backend/megusta`)** — **já migrado** no repositório: o
contrato é `email` e o scheduler usa `Usuario::getEmail`.

```java
// notificacao/AlertaEstoqueMensagem.java
public record AlertaEstoqueMensagem(
        String email,                       // antes: telefone
        List<AlertaEstoque> alertas
) {}
```

```java
// scheduler/VerificacaoEstoqueScheduler.java
List<String> destinatarios = usuarioRepository.findTopByOrderByIdDesc()
        .map(Usuario::getEmail)             // antes: Usuario::getTelefone
        .map(List::of)
        .orElseGet(List::of);
```

```java
// notificacao/NotificacaoEstoqueService.java
for (String email : emails) {
    if (email == null || !email.matches("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")) {
        log.warn("Destinatário sem e-mail válido ignorado: {}", email);
        continue;
    }
    alertaEstoquePublisher.publicar(email, abaixoDoMinimo);
}
```

O `exchange`/`routing key` continuam iguais (`megusta.estoque` /
`alerta.estoque`).

**Consumer (`me-gusta-microsservico/megusta-consumer/megusta-consumer`)** — a
versão de e-mail (que está em `config/patches/consumer-email.patch`, seção 10)
faz o seguinte:

```xml
<!-- pom.xml -->
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-mail</artifactId>
</dependency>
<dependency>
  <groupId>software.amazon.awssdk</groupId>
  <artifactId>sesv2</artifactId>
</dependency>
<!-- versão controlada pelo BOM software.amazon.awssdk:bom -->
```

```properties
# src/main/resources/application.properties
megusta.email.transport=${MAIL_TRANSPORT:smtp}
megusta.email.ses-region=${SES_REGION:us-east-1}
megusta.email.from=${SES_FROM:${SMTP_FROM:}}
megusta.email.override-to=${ALERTA_EMAIL_TO:}

spring.mail.host=${SMTP_HOST:}
spring.mail.port=${SMTP_PORT:587}
spring.mail.username=${SMTP_USERNAME:}
spring.mail.password=${SMTP_PASSWORD:}
spring.mail.default-encoding=UTF-8
spring.mail.properties.mail.smtp.auth=${SMTP_AUTH:true}
spring.mail.properties.mail.smtp.starttls.enable=${SMTP_STARTTLS:true}
spring.mail.properties.mail.smtp.starttls.required=${SMTP_STARTTLS:true}
spring.mail.properties.mail.smtp.ssl.enable=${SMTP_SSL:false}
spring.mail.properties.mail.smtp.connectiontimeout=10000
spring.mail.properties.mail.smtp.timeout=10000
spring.mail.properties.mail.smtp.writetimeout=10000
```

> No stack, a variável de ambiente `MEGUSTA_EMAIL_FROM` (definida no
> `docker-compose.yml` com o valor já resolvido pelo `deploy-swarm.sh`) tem
> precedência sobre `megusta.email.from` do `application.properties`. A
> propriedade abaixo é só o fallback para execução local sem o compose; não
> dependa dela no cluster.

```java
// EmailService.java (substitui o WhatsAppService)
@Service
public class EmailService {
  public String enviar(String destinatario, String resumo) {
    String to = overrideTo.isBlank() ? destinatario : overrideTo;
    // valida o e-mail (regex) e envia:
    //   MAIL_TRANSPORT=ses  -> SesV2Client.sendEmail(...) com credenciais padrão
    //   MAIL_TRANSPORT=smtp -> JavaMailSender.send(SimpleMailMessage)
    return to;
  }
}
```

```java
// AlertaEstoqueConsumer.java
@RabbitListener(queues = "${megusta.rabbitmq.queue}")
public void consumir(Message message) throws Exception {
  AlertaEstoqueMensagem dto = mapper.readValue(message.getBody(), AlertaEstoqueMensagem.class);
  String to = email.enviar(dto.email(), MensagemFormatter.resumo(dto));  // antes: whatsapp.enviar(...)
  log.info("Alerta de estoque enviado por e-mail para {}", to);
}
```

Ajustes que acompanham: o record `AlertaEstoqueMensagem` do consumer passa a ter
`String email`; `MensagemFormatter.telefone()` é removido; o arquivo
`exemplo-mensagem.json` passa a usar `"email"` no lugar de `"telefone"`.

### 10. Patch transitório do consumer (WhatsApp → e-mail)

Enquanto o repositório `me-gusta-microsservico` **ainda tiver**
`WhatsAppService.java` (ou seja, o time ainda não commitou a versão de e-mail), o
`deploy-swarm.sh` aplica automaticamente o patch versionado:

```text
config/patches/consumer-email.patch
```

- O patch é aplicado **depois** do `--sync-github` e **antes** do build, com
  `git apply --check` seguido de `git apply` (se falhar, o deploy aborta). O
  `build-images.sh` (build standalone) aplica o mesmo patch.
- Se o repo já estiver migrado (`WhatsAppService.java` não existe), o patch é
  **ignorado** — nada é sobrescrito.
- Quando o time commitar o consumer de e-mail, apague
  `config/patches/consumer-email.patch`: o bloco `apply_consumer_email_patch` do
  script passa a não encontrar nada e fica inerte.

> O patch também foi validado com `mvn test` (10 testes verdes: contrato,
> formatação, SES mockado e SMTP mockado).

### 11. Limpar a topologia antiga do WhatsApp

Depois do primeiro deploy com a fila nova, remova os objetos órfãos para não
acumular mensagens antigas (a fila antiga continua ligada ao mesmo exchange e
receberia uma cópia de cada alerta):

1. RabbitMQ UI → **Queues** → delete `megusta.whatsapp.alertas` e
   `megusta.whatsapp.alertas.dlq`.
2. **Exchanges** → delete `megusta.whatsapp.alertas.dlx`.

Nada mais usa esses nomes depois da migração.

---

## 🔧 Comandos Úteis Pós-Deploy

```bash
# Logs de um serviço
docker service logs -f megusta_frontend
docker service logs -f megusta_backend
docker service logs -f megusta_consumer
docker service logs -f megusta_database
docker service logs -f megusta_rabbitmq

# Status detalhado
docker stack services megusta
docker stack ps megusta --no-trunc

# Forçar reagendamento de um serviço
docker service update --force megusta_backend

# Ver o registry
curl http://<MANAGER_IP>:5000/v2/_catalog
curl http://<MANAGER_IP>:5000/v2/megusta-frontend/tags/list

# Redes e volumes do stack
docker network ls | grep megusta
docker volume ls | grep megusta

# Liberar espaço no bastion (cache de build / imagens antigas)
docker system prune -af
```

---

## 🐛 Troubleshooting Rápido

| Problema | Diagnóstico |
|----------|-------------|
| Serviço não sobe / fica `Pending` | `docker service ps megusta_<servico> --no-trunc` (veja o motivo: sem label? sem imagem? sem recurso?) |
| Nó não junta ao Swarm | Confirme o SG liberando `2377/tcp`, `7946/tcp+udp`, `4789/udp` entre os nós (já está em `seguranca.tf`). |
| `unknown flag: --role` ao juntar nó | O `docker swarm join` **não** aceita `--role` — o papel (manager/worker) vem do **token** (Manager Token vs Worker Token). **Já corrigido** no `join-swarm.sh` (o comando passa só `--token`). |
| Erro "no suitable node" | As labels não foram aplicadas — rode o `label-nodes.sh` de novo e confira `docker node ls`. |
| Backend não acessa o banco | `docker service logs megusta_backend`. O DB demora a inicializar no 1º boot. |
| Backend **parou de reiniciar** | A `restart_policy` usa `max_attempts: 3`: se falhar 3x em 120s ele para. Rode `docker service update --force megusta_backend` ou ajuste o `docker-compose.yml`. |
| Consumer em `0/2` / reiniciando | `docker service logs megusta_consumer --tail 100`. Causas comuns: imagem ainda é a de WhatsApp (rode `--rebuild`), `MAIL_TRANSPORT` com valor inválido, `SES_FROM` ausente/inválido (transporte `ses`) ou `SMTP_HOST`/`SMTP_FROM`/`SMTP_USERNAME`/`SMTP_PASSWORD` ausentes (transporte `smtp`). O `deploy-swarm.sh` já aborta antes do build nesses casos. |
| Consumer não recebe nada | Confirme que backend e consumer usam o **mesmo exchange/routing key** (`megusta.estoque` / `alerta.estoque`) e que existe **apenas 1 broker** RabbitMQ. Com 2 réplicas independentes, publisher e consumer caem em brokers diferentes e a mensagem se perde. |
| RabbitMQ `1/1` mas 5672/15672 recusam conexão e o log para em `Importing concurrently 1 users...` | **Bug do RabbitMQ 4.4.x no import via `management.load_definitions`** (reproduzido localmente com a imagem oficial `rabbitmq:4-management-alpine`, definitions mínimo e sem alarme de recurso). O `rabbitmq.conf` deste repo **não usa mais** `load_definitions` e o `definitions.json` foi removido: a topologia é declarada pelo backend (exchange) e pelo consumer (fila/binding/DLQ), e `admin`/`/` são semeados por `default_user`/`default_pass`/`default_vhost`. Se o log for de uma imagem antiga, rebuild só do RabbitMQ: `docker build -t <REGISTRY>/megusta-rabbitmq:latest config/docker/rabbitmq && docker push ... && docker service update --force --image <REGISTRY>/megusta-rabbitmq:latest megusta_rabbitmq`. Confirme `started TCP listener on [::]:5672` e `Server startup complete`. |
| Publicação bloqueada / `disk resource limit alarm set` no RabbitMQ | O `rabbitmq.conf` usa limites **absolutos** (`vm_memory_high_watermark.absolute = 256MB`, `disk_free_limit.absolute = 256MB`). Com `disk_free_limit.relative = 2.0` o limite virava 2× a RAM (~8 GB) e um disco de 2,7 GB disparava o alarme, bloqueando publishers mesmo com o broker de pé. |
| `Classic peer discovery backend: list of nodes does not contain the local node` no RabbitMQ | Ruído esperado se as linhas de `cluster_formation.*` estiverem ativas (o stack tem 1 broker). O `rabbitmq.conf` já as deixa comentadas. |
| `Unable to load credentials` (transporte `ses`) | O container não alcançou o IMDS. Confira `metadata_options` com `http_put_response_hop_limit = 2` nas instâncias backend (Terraform) e se a instância tem `iam_instance_profile`; depois recrie/atualize as instâncias (`tofu apply`) e force o serviço (`docker service update --force megusta_consumer`). |
| `MessageRejected: Email address is not verified` | A identidade ainda não foi verificada (link do e-mail não clicado) ou o destinatário está fora do sandbox. Veja `aws sesv2 get-email-identity --email-identity <email> --region us-east-1` e a seção [Amazon SES](#1-amazon-ses-opcional). |
| `AccessDenied` / `not authorized to perform ses:SendEmail` | A role do instance profile não tem permissão de SES. Confirme `aws sts get-caller-identity` de dentro do worker e a role anexada à instância. Alternativa: `MAIL_TRANSPORT=smtp`. |
| `AccessDenied ... ses:TagResource` ao criar a identidade | A role do AWS Academy permite criar a identidade, mas não aplicar tags. O `Terraform-full/ses.tf` **não envia tags de propósito**; se você adicionar um bloco `tags`, o `CreateEmailIdentity` inteiro falha. Remova as tags. |
| `AccessDenied ... ses:CreateEmailIdentity` / `VerifyEmailIdentity` | A role do laboratório não permite gerenciar identidades SES. Verifique o endereço em uma conta com permissão (console SES) ou use `MAIL_TRANSPORT=smtp`. |
| De repente **tudo** retorna `AccessDenied ... voc-cancel-cred` | As credenciais do laboratório expiraram/foram canceladas. Pegue credenciais novas em **AWS Details**, rode `aws configure` + `aws configure set aws_session_token ...` e repita o `tofu apply`. |
| Consumer conecta mas não envia (transporte `smtp`) | `MailAuthenticationException` = usuário/senha errados (no Gmail, precisa de **senha de app**); `MailSendException`/timeout = SG/NAT bloqueando 587, host/porta errados ou STARTTLS incompatível; `501/550` = remetente não autorizado no domínio. Após 3 tentativas a mensagem vai para `megusta.email.alertas.dlq`. |
| E-mail não chega | Veja o log do consumer (sem exceção = a API/SMTP aceitou), confira spam/lixo eletrônico e se `ALERTA_EMAIL_TO` não está redirecionando para outra caixa. Rode o teste direto com `aws sesv2 send-email` (seção 6) para isolar SES x stack. |
| Frontend não fala com backend | `docker run -it --rm --network megusta-net curlimages/curl curl -v http://backend:8080/v3/api-docs` |
| Erro de CORS no navegador | Não deveria ocorrer: o frontend usa `/api` (same-origin) e o nginx faz o proxy. Veja `docker service logs megusta_frontend`. |
| Build falha no bastion | Falta de RAM/disco. O bastion é `t3.medium`/30 GB; rode `docker system prune -af` e tente de novo. |
| `docker-compose não encontrado` | Não deveria ocorrer: é instalado no `user_data` do bastion. Se aparecer, a instância não foi recriada após o último apply. |
| Docker não sobe (`insecure registry :5000 is not valid: invalid host ""`) | Causa raiz: o teste de Swarm usava `grep -q "active"`, que também casa com **`inactive`** — numa instância nova o script achava que o Swarm já existia, lia `Swarm.NodeAddr` vazio e escrevia `daemon.json` com `":5000"`. **Já corrigido** (comparação exata `== "active"` + fallback de IP). Se acontecer em nó antigo: reescreva o `daemon.json` com o IP privado real (`MGR_IP=$(ip route get 8.8.8.8 \| awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')`) e `systemctl restart docker`. |
| Build usa o Dockerfile **do repo** em vez do da infra (ex.: log `Step 1/12 : RUN npm ci` e erro `npm ci ... in sync`, quando o nosso `frontend.Dockerfile` tem 14 steps) | Causa raiz: `sync_repo()` fazia `cd "$dest_dir"` **sem voltar**, então após o `--sync-github` o cwd virava o do último repo; o `ensure_dockerfiles()` recalculava `infra_dir` a partir do cwd errado e o `cp` falhava (silenciado por `\|\| true`), deixando o build usar o Dockerfile próprio do repo. **Já corrigido**: `sync_repo` roda o git em subshell (preserva o cwd), `ensure_dockerfiles` usa o `SCRIPT_DIR` resolvido no início, e a cópia de assets agora **aborta com erro** se a origem faltar. Sintoma clássico: só acontece no **2º** deploy em diante (no 1º o repo é clonado, sem `cd`). |
| `mvn clean package` falha no **`testCompile`** (`RelatorioServiceTest.java ... cannot be applied to given types`, `cannot find symbol`) | Os testes do repo estão desatualizados em relação ao código. `-DskipTests` só pula a **execução**, **não** a compilação de `src/test` — por isso o build ainda quebra. O `backend.Dockerfile` agora usa `-Dmaven.test.skip=true`, que pula compilação **e** execução. Correção definitiva: atualizar/remover esse teste no repo do backend. |
| `/bin/bash^M: bad interpreter: No such file or directory` ao rodar `./deploy-swarm.sh` | **CRLF (fim de linha do Windows) nos arquivos enviados via `scp`.** O kernel tenta executar `/bin/bash\r`, que não existe. Correção imediata: `sed -i 's/\r$//' *.sh` (ou `./fix-eol.sh`). Os `*.Dockerfile` também precisam ser normalizados, senão o **build falha silenciosamente** (sintoma: `docker stack services megusta` mostra tudo `0/1` e só o `rabbitmq` sobe `1/1`, porque a imagem dele veio antes do arquivo corrompido). Ver seção **Fim de linha (CRLF)** abaixo. |

---

## 🔤 Fim de linha (CRLF) — importante ao enviar do Windows

Os scripts e Dockerfiles deste diretório são feitos para rodar no **Linux**. Se forem editados/copiados de uma máquina Windows, podem chegar ao bastion com terminadores **CRLF (`\r\n`)** em vez de **LF (`\n`)**. Isso causa dois sintomas:

1. **Erro de interpreter** (o mais visível):
   ```
   -bash: ./deploy-swarm.sh: /bin/bash^M: bad interpreter: No such file or directory
   ```
   O kernel tenta executar `/bin/bash\r`, que não existe.

2. **Build silenciosamente quebrado** (o mais traiçoeiro): os `*.Dockerfile` com CRLF falham na fase de build. Sintoma: `docker stack services megusta` mostra `0/1` em quase tudo e **só o `rabbitmq` aparece `1/1`** (porque a imagem dele foi construída antes dos arquivos corrompidos). Nesse caso, `docker service ps megusta_backend --no-trunc` mostra `No such image` / `image not found`.

### Como resolver

O `fix-eol.sh` normaliza **todos** os arquivos de texto (scripts, Dockerfiles, `.cnf`, `.conf`, `.sql`, `.yml`, `.tf`, `.tpl`, `.json`, `.py`) para LF. É idempotente:

```bash
# No bastion-a, dentro de /home/ubuntu/config:
chmod +x fix-eol.sh
./fix-eol.sh
```

Os scripts principais (`deploy-swarm.sh`, `build-images.sh`, `join-swarm.sh`, `label-nodes.sh`) já chamam o `fix-eol.sh` automaticamente no início, então na prática **não é preciso rodar à mão** — basta que o `fix-eol.sh` esteja na mesma pasta.

### Outras formas de corrigir pontualmente

```bash
# Todos os .sh de uma vez:
sed -i 's/\r$//' *.sh
# Tudo (scripts + Dockerfiles + configs):
find . -type f \( -name '*.sh' -o -name '*.Dockerfile' -o -name 'Dockerfile*' -o -name '*.conf' -o -name '*.cnf' -o -name '*.sql' -o -name '*.yml' -o -name '*.tpl' \) -exec sed -i 's/\r$//' {} +
# Verificar se sobrou algum:
grep -rlU $'\r' . || echo "OK: nenhum CRLF"
```

No `vim`: `:set ff=unix` (ou `:set fileformat=unix`) seguido de `:wq`. Funciona, mas é **arquivo por arquivo** — fácil esquecer um.

### Prevenção

- O repositório tem um **`.gitattributes`** na raiz forçando `eol=lf` nos tipos sensíveis, então o Git não introduz CRLF no working tree.
- O repositório tem um **`.editorconfig`** na raiz, que faz os editores (VS Code, IntelliJ, Vim, Sublime) **já salvarem em LF** — evita que o CRLF entre antes mesmo do commit.
- Ao fazer `scp`/upload, use **modo binário**. Clientes gráficos (WinSCP, FileZilla) têm a opção "Transfer mode: Binary" / "Auto → Binary"; em modo texto eles reconvertem LF→CRLF no upload.
- Se o Git ainda avisar `LF will be replaced by CRLF`, ajuste: `git config core.autocrlf input`.

---

## 🔄 Rebuild e Atualização

```bash
# No bastion-a, como root, em /home/ubuntu/config:
./deploy-swarm.sh --rebuild --sync-github
```
- `--sync-github`: atualiza os repos (git fetch/reset) antes do build.
- `--rebuild`: força o rebuild das 5 imagens mesmo se já existirem no registry.
- Sem `--rebuild`, o script reaproveita as imagens já presentes no registry.

---

## ✅ Checklist Final

- [ ] `tofu apply` OK — e os **2 bastions foram recriados** (t3.medium, 30 GB, `docker-compose`)
- [ ] IP público atualizado do bastion-a obtido (`bastion_host_a_public_ip`)
- [ ] `megusta-key` + pasta `config/` enviados ao bastion-a (ETAPA 1)
- [ ] `config/.env` criado a partir de `.env.example` com `MAIL_TRANSPORT=smtp`, `SMTP_HOST`/`SMTP_FROM` e credenciais (Gmail: senha de app)
- [ ] `ALERTA_EMAIL_TO=henry.silva@sptech.school` para o teste chegar na caixa correta
- [ ] (Opcional, só em conta com permissão SES) identidade SES criada e verificada: `enable_ses_email_identity = true` + clique no link; `tofu output ses_email_identity_verified_for_sending` = `true`
- [ ] `./deploy-swarm.sh --rebuild --sync-github` executado (ETAPA 2)
- [ ] 4 valores anotados: Manager Token, Worker Token, Manager IP (privado), Registry URL
- [ ] bastion-b juntou como **manager**
- [ ] web-a, web-b, backend-a, backend-b, database-a juntaram como **worker**
- [ ] `label-nodes.sh` executado → todos os 7 nós com `az` e `role`
- [ ] `docker stack services megusta` → frontend/backend/consumer `2/2`, database/rabbitmq `1/1`
- [ ] `docker service logs megusta_consumer` mostra conexão AMQP e listener da fila
- [ ] Teste de envio direto pelo SES funcionou (`aws sesv2 send-email`) e o e-mail chegou na caixa
- [ ] ALB com os 2 targets `healthy`
- [ ] Acesso via `http://<ALB_DNS>` funcionando
- [ ] Registry acessível: `curl http://<MANAGER_IP>:5000/v2/_catalog`

---

## 📝 Notas Importantes

1. **Local Registry** — registry Docker na porta 5000 no bastion-a (dados em `/opt/megusta/registry`). As imagens são tagueadas com o **IP privado do manager** (`<MANAGER_IP>:5000/...`) para que os workers consigam puxá-las. O `join-swarm.sh` adiciona esse endereço em `insecure-registries`, e o SG do manager libera a porta 5000 dentro da VPC. Para produção, use ECR/Docker Hub.
2. **NAT Gateway** — 1 NAT gerenciado (AZ A), alta disponibilidade nativa da AWS. Route tables privadas (AZ A + AZ B) apontam `0.0.0.0/0` para ele.
3. **Database é single-instance** — instância dedicada `database-a` (AZ A), sem HA/RDS por decisão de arquitetura.
4. **RabbitMQ** — sobe **1 réplica** com a config (`rabbitmq.conf`) **embutida na imagem** `megusta-rabbitmq` (bind mounts relativos não funcionam em Swarm). O `rabbitmq.conf` **não carrega definitions**: no RabbitMQ 4.4.x o import via `management.load_definitions` trava o boot em `Importing concurrently 1 users...`. A topologia é declarada pelos serviços no startup (backend cria o exchange `megusta.estoque`; consumer cria a fila `megusta.email.alertas`, o binding `alerta.estoque` e a DLQ) e o usuário `admin`/vhost `/` vêm de `default_user`/`default_pass`/`default_vhost`. Antes eram 2 réplicas, mas o clustering por `rabbit@rabbitmq-1/2` **não formava cluster** (hostnames dinâmicos no Swarm). Com o consumer, manter 2 brokers independentes faria o VIP `rabbitmq` entregar o publisher em um broker e o consumer em outro, **perdendo mensagens**. Por isso o stack usa 1 broker único e funcional. Para HA real, o próximo passo é implementar clustering/quorum de verdade (3 nós ou um broker gerenciado).
5. **Consumer** — é o serviço `megusta_consumer`, imagem `megusta-consumer` (Java 21 / Spring Boot), construído a partir de `Miralhaz/me-gusta-microsservico` na subpasta `megusta-consumer/megusta-consumer` (com o patch transitório `config/patches/consumer-email.patch` enquanto o repo oficial não migra). Não expõe porta, não acessa MySQL e roda nos nós `role=backend` (2 réplicas). O contrato com o backend é `RABBITMQ_EXCHANGE=megusta.estoque`, `RABBITMQ_ROUTING_KEY=alerta.estoque` e `RABBITMQ_QUEUE=megusta.email.alertas`. O envio usa `MAIL_TRANSPORT=smtp` por padrão no AWS Academy (Gmail/365 com senha de app); `MAIL_TRANSPORT=ses` fica disponível para contas cuja role permita a API do SES. Não há mudança de Security Group: o consumer fala com o RabbitMQ pela rede overlay `megusta-net` e com o SES/SMTP pela saída liberada (egress all) via NAT.
6. **Secrets** — hardcoded no compose (`sptech`, `sptech_root_2024`, `admin`) por simplicidade. Em produção, migre para Docker Secrets / AWS Secrets Manager. No transporte `ses` não há senha de e-mail no stack (credenciais vêm da role da instância). Se usar `smtp`, o `SMTP_PASSWORD` fica fora do compose (via `config/.env`, não versionado), mas ainda como variável de ambiente.
7. **Logs** — Fluent Bit nas instâncias envia logs para o bucket S3 raw. Os containers usam o driver `json-file` (max-size 10m, max-file 3).
8. **Monitoramento** — CloudWatch + SNS configurados via Terraform.
9. **Hostnames** — o `user_data` de cada nó define `hostnamectl set-hostname megusta-prod-us1-<função>`, o mesmo das tags `Name` do Terraform. É obrigatório porque o Swarm registra o nó pelo hostname do SO e o `label-nodes.sh` localiza os nós por esse nome. Como o `user_data` só roda no boot, instâncias antigas precisam ser **recriadas**.
10. **Build Context e Dockerfiles** — o código não está na raiz dos repos:
   - frontend: `me-gusta-frontend/me-gusta-frontend` (Node 22 → Nginx)
   - backend:  `me-gusta-backend/megusta` (Maven 3.9 + Java 21 → JRE 21)
   - database: raiz de `me-gusta-database` (a infra fornece o `Dockerfile.database` e os assets)
   - consumer: `me-gusta-microsservico/megusta-consumer/megusta-consumer` (a infra fornece o `consumer.Dockerfile`)
   Os scripts **copiam automaticamente** os Dockerfiles/`nginx.conf`/assets de `config/docker/` para os repos clonados.
11. **Frontend → Backend** — o `src/provider/api.js` do frontend usa `baseURL: "http://localhost:8080"` (hardcoded). No `frontend.Dockerfile` essa string é reescrita para o prefixo relativo **`/api`**, e o `nginx.conf` faz reverse proxy de `/api/*` para o serviço `backend:8080` na rede overlay. Assim o navegador nunca usa `localhost` e as chamadas ficam **same-origin** (resolve o CORS).
12. **Banco (front/back)** — o backend recebe `SPRING_DATASOURCE_URL=jdbc:mysql://database:3306/megusta`, `SPRING_DATASOURCE_USERNAME=megusta_admin`, `SPRING_DATASOURCE_PASSWORD=sptech` via env do compose (env tem precedência sobre o `application.properties` do repo).
13. **Healthchecks** — o backend **não** tem `spring-boot-starter-actuator`, então `/actuator/health` dá 404. O healthcheck do compose usa `/v3/api-docs` (permitAll), e a imagem do backend instala `curl`.
14. **Init-scripts do banco** — o `Dockerfile.database` copia os `init-scripts/*.sql` para `/docker-entrypoint-initdb.d/` **dentro da imagem**. Rodam **apenas no primeiro boot** com volume vazio; em re-deploy os dados persistem.
15. **Caminho do navegador (ALB → Frontend)** — o ALB aponta para as instâncias **web** na porta 80. Nessas instâncias, o **nginx do host** (instalado via `user_data`) faz reverse proxy para `http://127.0.0.1:8080`, que é o host port publicado pelo serviço `frontend` (`mode: host`). Dentro do container, o nginx serve a SPA e encaminha `/api` para `backend:8080`. O health check do ALB é `GET /health`.
16. **Regras de Security Group do Swarm** — `Terraform-full/seguranca.tf` libera, entre os nós (CIDR da VPC), `2377/tcp` (join/management), `7946/tcp+udp` (gossip) e `4789/udp` (overlay VXLAN). Sem elas o `docker swarm join` falha. O consumer usa essas mesmas regras; não é necessário abrir porta para ele.
17. **Insecure Registry** — o `join-swarm.sh` já configura isso automaticamente; não faça manualmente.
