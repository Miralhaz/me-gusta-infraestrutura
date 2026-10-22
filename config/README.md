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
├── docker/
│   ├── docker-compose.yml      # Stack principal do Swarm
│   ├── Dockerfile.database     # Imagem customizada MySQL (repo do banco NÃO tem Dockerfile)
│   ├── frontend.Dockerfile     # Dockerfile do frontend (copiado para a subpasta do repo)
│   ├── backend.Dockerfile      # Dockerfile do backend  (copiado para a subpasta do repo)
│   ├── nginx.conf              # SPA + reverse proxy /api -> backend:8080 (copiado p/ frontend)
│   ├── config/
│   │   └── mysql/
│   │       └── custom.cnf      # Configuração MySQL otimizada
│   ├── rabbitmq/
│   │   ├── Dockerfile          # Imagem customizada RabbitMQ (config embutida)
│   │   ├── rabbitmq.conf       # Configuração RabbitMQ
│   │   └── definitions.json    # Filas, exchanges, bindings, policies
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
| **backend-a** | megusta-prod-us1-backend-a | Worker | az-a | backend (1 replica) |
| **backend-b** | megusta-prod-us1-backend-b | Worker | az-b | backend (1 replica) |
| **database-a** | megusta-prod-us1-database-a | Worker | az-a | database (1 replica) |

- **Rede:** 1 NAT Gateway gerenciado (AZ A); route tables privadas (AZ A + AZ B) apontam `0.0.0.0/0` para ele.
- **7 instâncias EC2:** 2 managers + 5 workers. Os bastions ficam em subnets públicas (com Elastic IP); os 5 workers ficam em subnets privadas (**sem IP público**).

---

## ✅ Pré-requisitos (antes de qualquer coisa)

- [ ] `tofu apply` concluído (rodado **na sua máquina**, a partir do `terraform.tfvars`). 7 instâncias + NAT Gateway + ALB.
- [ ] Chave SSH privada em `Terraform-full/megusta-key`.
- [ ] Buckets S3 criados manualmente: `megusta-raw-us-east-1`, `megusta-trusted-us-east-1`, `megusta-curated-us-east-1`.
- [ ] Repositórios do GitHub acessíveis (públicos): `Miralhaz/me-gusta-frontend`, `Miralhaz/me-gusta-backend`, `Miralhaz/me-gusta-database`.

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
> **build das 4 imagens**. Por isso ele é `t3.medium` com 30 GB. Se fizer muitos
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
5. ✅ Clona os 3 repositórios do GitHub em `/opt/megusta/src/`.
6. ✅ Copia os Dockerfiles/assets da infra para dentro dos repos clonados —
   o código **não** está na raiz dos repos:
   - frontend → `me-gusta-frontend/me-gusta-frontend` (recebe `Dockerfile` + `nginx.conf`)
   - backend → `me-gusta-backend/megusta` (recebe `Dockerfile`)
   - database → raiz de `me-gusta-database` (recebe `Dockerfile` + assets)
7. ✅ Faz **build das 4 imagens + push** para o registry:
   - `<MANAGER_IP>:5000/megusta-frontend:latest`
   - `<MANAGER_IP>:5000/megusta-backend:latest`
   - `<MANAGER_IP>:5000/megusta-database:latest`
   - `<MANAGER_IP>:5000/megusta-rabbitmq:latest`
8. ✅ Faz `docker stack deploy` do stack `megusta`.

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
| megusta_database | 1/1 | database-a (az-a) |
| megusta_rabbitmq | 2/2 | workers (spread az-a/az-b) |

**Testes de saúde (a partir do bastion-a):**
```bash
docker run -it --rm --network megusta-net curlimages/curl curl -s http://frontend/health
docker run -it --rm --network megusta-net curlimages/curl curl -s http://backend:8080/v3/api-docs
docker run -it --rm --network megusta-net curlimages/curl curl -s http://frontend/api/insumos
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

## 🔧 Comandos Úteis Pós-Deploy

```bash
# Logs de um serviço
docker service logs -f megusta_frontend
docker service logs -f megusta_backend
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
| Frontend não fala com backend | `docker run -it --rm --network megusta-net curlimages/curl curl -v http://backend:8080/v3/api-docs` |
| Erro de CORS no navegador | Não deveria ocorrer: o frontend usa `/api` (same-origin) e o nginx faz o proxy. Veja `docker service logs megusta_frontend`. |
| Build falha no bastion | Falta de RAM/disco. O bastion é `t3.medium`/30 GB; rode `docker system prune -af` e tente de novo. |
| `docker-compose não encontrado` | Não deveria ocorrer: é instalado no `user_data` do bastion. Se aparecer, a instância não foi recriada após o último apply. |
| Docker não sobe (`insecure registry :5000 is not valid: invalid host ""`) | Causa raiz: o teste de Swarm usava `grep -q "active"`, que também casa com **`inactive`** — numa instância nova o script achava que o Swarm já existia, lia `Swarm.NodeAddr` vazio e escrevia `daemon.json` com `":5000"`. **Já corrigido** (comparação exata `== "active"` + fallback de IP). Se acontecer em nó antigo: reescreva o `daemon.json` com o IP privado real (`MGR_IP=$(ip route get 8.8.8.8 \| awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')`) e `systemctl restart docker`. |
| Build usa o Dockerfile **do repo** em vez do da infra (ex.: log `Step 1/12 : RUN npm ci` e erro `npm ci ... in sync`, quando o nosso `frontend.Dockerfile` tem 14 steps) | Causa raiz: `sync_repo()` fazia `cd "$dest_dir"` **sem voltar**, então após o `--sync-github` o cwd virava o do último repo; o `ensure_dockerfiles()` recalculava `infra_dir` a partir do cwd errado e o `cp` falhava (silenciado por `\|\| true`), deixando o build usar o Dockerfile próprio do repo. **Já corrigido**: `sync_repo` roda o git em subshell (preserva o cwd), `ensure_dockerfiles` usa o `SCRIPT_DIR` resolvido no início, e a cópia de assets agora **aborta com erro** se a origem faltar. Sintoma clássico: só acontece no **2º** deploy em diante (no 1º o repo é clonado, sem `cd`). |
| `mvn clean package` falha no **`testCompile`** (`RelatorioServiceTest.java ... cannot be applied to given types`, `cannot find symbol`) | Os testes do repo estão desatualizados em relação ao código. `-DskipTests` só pula a **execução**, **não** a compilação de `src/test` — por isso o build ainda quebra. O `backend.Dockerfile` agora usa `-Dmaven.test.skip=true`, que pula compilação **e** execução. Correção definitiva: atualizar/remover esse teste no repo do backend. |
| `/bin/bash^M: bad interpreter: No such file or directory` ao rodar `./deploy-swarm.sh` | **CRLF (fim de linha do Windows) nos arquivos enviados via `scp`.** O kernel tenta executar `/bin/bash\r`, que não existe. Correção imediata: `sed -i 's/\r$//' *.sh` (ou `./fix-eol.sh`). Os `*.Dockerfile` também precisam ser normalizados, senão o **build falha silenciosamente** (sintoma: `docker stack services megusta` mostra tudo `0/1` e só o `rabbitmq` sobe `2/2`, porque a imagem dele veio antes do arquivo corrompido). Ver seção **Fim de linha (CRLF)** abaixo. |

---

## 🔤 Fim de linha (CRLF) — importante ao enviar do Windows

Os scripts e Dockerfiles deste diretório são feitos para rodar no **Linux**. Se forem editados/copiados de uma máquina Windows, podem chegar ao bastion com terminadores **CRLF (`\r\n`)** em vez de **LF (`\n`)**. Isso causa dois sintomas:

1. **Erro de interpreter** (o mais visível):
   ```
   -bash: ./deploy-swarm.sh: /bin/bash^M: bad interpreter: No such file or directory
   ```
   O kernel tenta executar `/bin/bash\r`, que não existe.

2. **Build silenciosamente quebrado** (o mais traiçoeiro): os `*.Dockerfile` com CRLF falham na fase de build. Sintoma: `docker stack services megusta` mostra `0/1` em quase tudo e **só o `rabbitmq` aparece `2/2`** (porque a imagem dele foi construída antes dos arquivos corrompidos). Nesse caso, `docker service ps megusta_backend --no-trunc` mostra `No such image` / `image not found`.

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
- `--rebuild`: força o rebuild das 4 imagens mesmo se já existirem no registry.
- Sem `--rebuild`, o script reaproveita as imagens já presentes no registry.

---

## ✅ Checklist Final

- [ ] `tofu apply` OK — e os **2 bastions foram recriados** (t3.medium, 30 GB, `docker-compose`)
- [ ] IP público atualizado do bastion-a obtido (`bastion_host_a_public_ip`)
- [ ] `megusta-key` + pasta `config/` enviados ao bastion-a (ETAPA 1)
- [ ] `./deploy-swarm.sh --rebuild --sync-github` executado (ETAPA 2)
- [ ] 4 valores anotados: Manager Token, Worker Token, Manager IP (privado), Registry URL
- [ ] bastion-b juntou como **manager**
- [ ] web-a, web-b, backend-a, backend-b, database-a juntaram como **worker**
- [ ] `label-nodes.sh` executado → todos os 7 nós com `az` e `role`
- [ ] `docker stack services megusta` → 2/2, 2/2, 1/1, 2/2
- [ ] ALB com os 2 targets `healthy`
- [ ] Acesso via `http://<ALB_DNS>` funcionando
- [ ] Registry acessível: `curl http://<MANAGER_IP>:5000/v2/_catalog`

---

## 📝 Notas Importantes

1. **Local Registry** — registry Docker na porta 5000 no bastion-a (dados em `/opt/megusta/registry`). As imagens são tagueadas com o **IP privado do manager** (`<MANAGER_IP>:5000/...`) para que os workers consigam puxá-las. O `join-swarm.sh` adiciona esse endereço em `insecure-registries`, e o SG do manager libera a porta 5000 dentro da VPC. Para produção, use ECR/Docker Hub.
2. **NAT Gateway** — 1 NAT gerenciado (AZ A), alta disponibilidade nativa da AWS. Route tables privadas (AZ A + AZ B) apontam `0.0.0.0/0` para ele.
3. **Database é single-instance** — instância dedicada `database-a` (AZ A), sem HA/RDS por decisão de arquitetura.
4. **RabbitMQ** — sobe 2 réplicas, com a config (`rabbitmq.conf` + `definitions.json`) **embutida na imagem** `megusta-rabbitmq` (bind mounts relativos não funcionam em Swarm). **Observações:** o backend **não** possui dependência AMQP (o RabbitMQ é parte da arquitetura, mas não é consumido pela aplicação), e o clustering por `rabbit@rabbitmq-1/2` **não forma cluster** no Swarm (os hostnames dos containers são dinâmicos). Cada réplica sobe normalmente, de forma independente.
5. **Secrets** — hardcoded no compose (`sptech`, `sptech_root_2024`, `admin`) por simplicidade. Em produção, migre para Docker Secrets / AWS Secrets Manager.
6. **Logs** — Fluent Bit nas instâncias envia logs para o bucket S3 raw. Os containers usam o driver `json-file` (max-size 10m, max-file 3).
7. **Monitoramento** — CloudWatch + SNS configurados via Terraform.
8. **Hostnames** — o `user_data` de cada nó define `hostnamectl set-hostname megusta-prod-us1-<função>`, o mesmo das tags `Name` do Terraform. É obrigatório porque o Swarm registra o nó pelo hostname do SO e o `label-nodes.sh` localiza os nós por esse nome. Como o `user_data` só roda no boot, instâncias antigas precisam ser **recriadas**.
9. **Build Context e Dockerfiles** — o código não está na raiz dos repos:
   - frontend: `me-gusta-frontend/me-gusta-frontend` (Node 22 → Nginx)
   - backend:  `me-gusta-backend/megusta` (Maven 3.9 + Java 21 → JRE 21)
   - database: raiz de `me-gusta-database` (a infra fornece o `Dockerfile.database` e os assets)
   Os scripts **copiam automaticamente** os Dockerfiles/`nginx.conf`/assets de `config/docker/` para os repos clonados.
10. **Frontend → Backend** — o `src/provider/api.js` do frontend usa `baseURL: "http://localhost:8080"` (hardcoded). No `frontend.Dockerfile` essa string é reescrita para o prefixo relativo **`/api`**, e o `nginx.conf` faz reverse proxy de `/api/*` para o serviço `backend:8080` na rede overlay. Assim o navegador nunca usa `localhost` e as chamadas ficam **same-origin** (resolve o CORS).
11. **Banco (front/back)** — o backend recebe `SPRING_DATASOURCE_URL=jdbc:mysql://database:3306/megusta`, `SPRING_DATASOURCE_USERNAME=megusta_admin`, `SPRING_DATASOURCE_PASSWORD=sptech` via env do compose (env tem precedência sobre o `application.properties` do repo).
12. **Healthchecks** — o backend **não** tem `spring-boot-starter-actuator`, então `/actuator/health` dá 404. O healthcheck do compose usa `/v3/api-docs` (permitAll), e a imagem do backend instala `curl`.
13. **Init-scripts do banco** — o `Dockerfile.database` copia os `init-scripts/*.sql` para `/docker-entrypoint-initdb.d/` **dentro da imagem**. Rodam **apenas no primeiro boot** com volume vazio; em re-deploy os dados persistem.
14. **Caminho do navegador (ALB → Frontend)** — o ALB aponta para as instâncias **web** na porta 80. Nessas instâncias, o **nginx do host** (instalado via `user_data`) faz reverse proxy para `http://127.0.0.1:8080`, que é o host port publicado pelo serviço `frontend` (`mode: host`). Dentro do container, o nginx serve a SPA e encaminha `/api` para `backend:8080`. O health check do ALB é `GET /health`.
15. **Regras de Security Group do Swarm** — `Terraform-full/seguranca.tf` libera, entre os nós (CIDR da VPC), `2377/tcp` (join/management), `7946/tcp+udp` (gossip) e `4789/udp` (overlay VXLAN). Sem elas o `docker swarm join` falha.
16. **Insecure Registry** — o `join-swarm.sh` já configura isso automaticamente; não faça manualmente.
