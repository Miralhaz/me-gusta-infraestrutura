# Teste de Carga — MeGusta (Comp. Nuvem)

Plano JMeter para medir o MeGusta **implantado no Swarm**, passando pelo ALB,
com carga mista de leitura (página inicial), escrita (cadastro de usuário) e
sondas de saúde.

> Este diretório **não cria infraestrutura**. Ele testa o ambiente que já está
> no ar. Se o alvo não estiver saudável, o teste é interrompido em vez de gerar
> números de um ambiente quebrado.

---

## 1. O que é automatizado e o que é manual

| Etapa | Como |
|---|---|
| Deploy do stack, labels, ALB, banco | **Manual** (ver `../README.md`) |
| Confirmar que os serviços estão `2/2`/`1/1` | **Manual** (comandos abaixo) |
| Gerar CSV de e-mails únicos | Automatizado (`scripts/gerar-usuarios.sh`) |
| Executar o JMeter e gerar JTL + dashboard HTML | Automatizado (`scripts/rodar-carga.sh`) |
| Resumir latência, erros e vazão | Automatizado (`scripts/analisar-jtl.py`) |
| Conferir persistência no MySQL | Automatizado (`scripts/contar-usuarios.sh`) |
| Remover os usuários de teste | Automatizado (`scripts/limpar-usuarios.sh`) |
| Coletar evidências para o relatório | **Manual** (dashboard/tabela/JTL) |
| Interpretar e escrever a conclusão | **Manual** |

---

## 2. Caminho exercitado

```text
JMeter (bastion ou sua máquina)
   |
   v
ALB  (porta 80 -> target group web-a / web-b)
   |
   v
nginx do frontend  (GET / e proxy /api/*)
   |
   v
backend Spring Boot (backend-a / backend-b)
   |
   v
MySQL (database-a)
```

- `GET /` mede o nginx + SPA.
- `GET /health` é o mesmo endpoint usado pelo health check do ALB.
- `POST /api/usuarios` mede o caminho completo de escrita (nginx → backend →
  MySQL) e é público (`permitAll`), portanto não exige token.

> Não use `/usuarios` direto no ALB: o ALB só publica o nginx. O caminho
> público é `/api/usuarios`.

---

## 3. Pré-requisitos (manuais)

1. Stack implantado e Saudável. No **bastion-a**:

   ```bash
   docker stack services megusta
   # Esperado: backend 2/2, frontend 2/2, consumer 2/2,
   #           database 1/1, rabbitmq 1/1
   docker stack ps megusta --no-trunc | grep -v "Running"
   ```

2. ALB respondendo. O DNS do ALB sai do output do Terraform na sua máquina
   (ou do console AWS):

   ```bash
   ALB_DNS=$(tofu -chdir=Terraform-full output -raw alb_dns_name)
   curl -i "http://${ALB_DNS}/health"     # 200 healthy
   curl -i "http://${ALB_DNS}/"           # 200 (HTML do frontend)
   ```

3. O consumer precisa estar `2/2`. Ele não participa do cadastro, mas se estiver
   reiniciando o stack está incompleto — e um alerta de estoque publicado no
   RabbitMQ retornaria `404` porque a topologia não foi declarada. Veja a seção
   “Consumer e o 404 no RabbitMQ” no `../README.md`.

4. Ferramenta de carga (escolha **uma**):

   - **Docker** (recomendado no bastion): `docker pull justb4/jmeter:5.5`
   - **JMeter local**: Apache JMeter **5.5+** com Java 8+ (`jmeter -v`; o plano
     foi validado com 5.6.3)

5. Rode o JMeter **fora dos containers da aplicação** (bastion ou sua máquina).
   Rodar dentro do container do backend faz o JMeter competir por CPU com o
   próprio serviço medido e invalida o resultado.

6. Limpeza: o cadastro grava usuários reais no MySQL. Use os scripts de limpeza
   ao final e nunca aponte o teste para dados de produção sem combinar antes.

---

## 4. Execução rápida (no bastion-a)

Obtenha o DNS do ALB **na sua máquina** (ou no console AWS) e passe para o
script. O bastion normalmente não tem o `Terraform-full` nem o `tofu`.

```bash
# NA SUA MAQUINA:
tofu -chdir=Terraform-full output -raw alb_dns_name
```

```bash
# NO BASTION:
cd ~/config/loadtest
chmod +x scripts/*.sh
./scripts/rodar-carga.sh --host <ALB_DNS>
```

O script:

1. valida `http://<host>/health` (aborta se não responder `200`);
2. gera `usuarios.csv` com e-mails únicos (prefixo por timestamp);
3. executa o plano com 10 threads de navegação + 10 de cadastro + 1 sonda,
   ramp de 30 s e duração de 120 s;
4. grava JTL, log e dashboard HTML em `resultados/<timestamp>-<host>/`;
5. imprime a tabela de latência/erros/vazão e o comando de limpeza.

Saída esperada (valores ilustrativos):

```text
==> Verificando alvo: http://meu-alb.elb.amazonaws.com/health
    OK: /health respondeu 200
==> Gerando 2400 usuarios unicos
==> JMeter via Docker: justb4/jmeter:5.5
==> Duracao: 120s | ramp: 30s
...
Amostra                                    #   Err    %Err     Media      p50 ...
01 GET /                                1420     0    0.00     118.4     ...
02 POST /api/usuarios                    810     0    0.00    1850.7     ...
03 GET /health                            12     0    0.00      25.1     ...
TOTAL (todas as amostras)               2242     0    0.00     790.2     ...
```

### 4.1 Rodar da sua máquina (sem bastion)

Com JMeter local:

```bash
cd config/loadtest
./scripts/rodar-carga.sh --host "$(tofu -chdir=../../Terraform-full output -raw alb_dns_name)" \
  --modo local --jmeter /caminho/apache-jmeter/bin/jmeter
```

No Windows (Git Bash), use o launcher Unix do JMeter e defina `JAVA_HOME`
(o launcher `.bat` não é executável pelo script):

```bash
export JAVA_HOME=/c/Users/<voce>/.jdks/corretto-21   # ou outro JDK 8+
./scripts/rodar-carga.sh --host "<alb-dns>" --modo local \
  --jmeter /c/apache-jmeter/bin/jmeter
```

O modo Docker é voltado ao Linux (bastion). No Docker Desktop do Windows o
`--network host` não existe; prefira JMeter local. A análise automática usa
`python3`, `python` ou `py` (valida o interpretador antes de usar); se nenhum
estiver disponível, o JTL/dashboard continuam sendo gerados e a análise pode
ser feita depois com `analisar-jtl.py`.

---

## 5. Parâmetros

Todos podem ser passados por linha de comando ou variável de ambiente.

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `--host` / `ALVO_HOST` | — | DNS do ALB ou IP (obrigatório) |
| `--port` / `ALVO_PORT` | `80` | Porta do ALB |
| `--protocolo` | `http` | `http` ou `https` (ALB atual é HTTP) |
| `--threads` | `10` | Threads do grupo Navegação (`GET /`) |
| `--threads-cadastro` | `10` | Threads do grupo Cadastro |
| `--threads-saude` | `1` | Threads do grupo Sondas |
| `--duracao` | `120` | Duração em segundos (todos os grupos) |
| `--ramp` | `30` | Ramp-up em segundos |
| `--usuarios` | `threads_cadastro × duracao × 2` | Linhas do CSV gerado |
| `--csv` | — | Usa um CSV existente (cabeçalho `nome,email,senha,telefone`) |
| `--prefixo` | `carga-<timestamp>` | Prefixo dos e-mails gerados |
| `--resultados` | `loadtest/resultados` | Diretório base dos resultados |
| `--modo` | `auto` | `auto`, `local` ou `docker` |
| `--jmeter` | — | Caminho do binário `jmeter` |
| `--imagem-jmeter` | `justb4/jmeter:5.5` | Imagem usada no modo Docker |
| `--docker-user` | — | `UID:GID` do container JMeter (evita arquivos root no volume) |
| `--max-erro-pct` | `2` | Limite de erro para o resumo automático |
| `--max-p95-ms` | `5000` | Limite de p95 (ms) para o resumo automático |
| `--sem-check` | — | Pula a verificação de `/health` (não recomendado) |
| `--checar-servicos` | — | Mostra `docker service ls` antes do teste |

O CSV é consumido **sem reciclagem** (`recycle=false`): se as linhas acabarem
antes do fim do teste, as threads de cadastro param. Por isso o padrão gera 2×
a capacidade teórica. Se aparecer `409`, o CSV foi reutilizado — gere outro.

---

## 6. Evidências para o relatório

Cada execução cria:

```text
resultados/20261115T143000-meu-alb.elb.amazonaws.com/
├── parametros.txt      # threads, duração, host, commit
├── usuarios.csv        # dados usados (sem dados reais)
├── resultados.jtl      # amostras brutas do JMeter
├── jmeter.log          # log da execução
├── analise.txt         # tabela do analisador
└── html/index.html     # dashboard HTML do JMeter
```

### 6.1 Sem baixar arquivos (recomendado)

Sirva o diretório no bastion e abra por túnel SSH:

```bash
# NO BASTION, dentro do diretório da execução:
cd ~/config/loadtest/resultados/20261115T143000-meu-alb.elb.amazonaws.com
python3 -m http.server 8000 --bind 127.0.0.1
```

```bash
# NA SUA MÁQUINA, em outro terminal:
ssh -i Terraform-full/megusta-key -L 8000:localhost:8000 ubuntu@<BASTION_A_IP>
# depois abra: http://localhost:8000/html/
```

O dashboard já contém gráficos de latência ao longo do tempo, throughput,
percentis e taxa de erro — é a evidência principal. `analise.txt` pode ser lido
sem download:

```bash
ssh -i Terraform-full/megusta-key ubuntu@<BASTION_A_IP> \
  'cat ~/config/loadtest/resultados/<run>/analise.txt'
```

### 6.2 Evidências mínimas sugeridas

1. `docker stack services megusta` (5 serviços saudáveis) **antes** do teste.
2. Saída do `rodar-carga.sh` (validação de `/health`, parâmetros, tabela).
3. `html/index.html` (dashboard) ou o `analise.txt`.
4. Contagem no banco antes/depois (`contar-usuarios.sh`).
5. Comando de limpeza executado e contagem zerada.

### 6.3 Rodar mais de uma vez

Para o relatório, execute **3 vezes** com os mesmos parâmetros:

- descarte a 1ª execução (aquecimento de JIT/cache);
- reporte a mediana das execuções 2 e 3;
- não some execuções diferentes: cada uma é uma amostra.

Para gerar a tabela já em Markdown (pronta para colar no relatório):

```bash
python3 scripts/analisar-jtl.py resultados/<run>/resultados.jtl --formato markdown
```

Use `--formato json` para automatizar/plotar os números em outra ferramenta.

---

## 7. Interpretação e critérios de aceite

O analisador imprime, por amostra: total, erros, `%` de erro, média, p50, p90,
p95, p99, mínimo, máximo, req/s e distribuição de códigos HTTP.

Critérios sugeridos (ajuste ao enunciado da disciplina):

| Critério | Limite inicial |
|---|---|
| `/health` durante o teste | sempre `200` |
| Erros HTTP | ≤ 2% das amostras |
| p95 do cadastro | ≤ 5000 ms |
| p95 da navegação | ≤ 1000 ms |
| Vazão do cadastro | ≥ 1 req/s (comparar com a linha de base) |
| Usuários no banco | igual ao nº de respostas `201` |

O script retorna código `2` quando `--max-erro-pct` ou `--max-p95-ms` são
violados. Isso não apaga as evidências: o dashboard e o JTL continuam gerados.

Leitura rápida:

- **p95 alto e CPU do backend saturada** → gargalo na aplicação ou no MySQL.
- **Latência sobe com o tempo e erros `502/504`** → backend/DB saturado ou
  pool de conexões esgotado; verifique `docker service logs megusta_backend`.
- **`400`** → payload inválido (senha/telefone); confira o CSV.
- **`409`** → e-mail repetido; o CSV não é único ou foi reaproveitado.
- **`404`** em `/api/usuarios` → caminho errado (use `/api/...`) ou nginx sem o
  proxy; confira `config/docker/nginx.conf`.
- **`/health` falha no meio** → uma instância web saiu do ar; o ALB pode estar
  balanceando para um target não saudável.
- **Vazão da navegação muito maior que a do cadastro** é esperado: o cadastro
  grava no MySQL, que é instância única.

---

## 8. Conferir e limpar o banco

O banco roda no nó **database-a** e não publica porta no host. Por isso os
scripts sobem um **container cliente efêmero** na rede overlay `megusta-net`
(attachable) e conectam em `database:3306`. Execute no bastion-a (manager), com
o stack ativo. A imagem `mysql:8.0` é usada como cliente (o Docker baixa se
necessário; pode ser trocada via `DB_CLIENT_IMAGE`).

```bash
cd ~/config/loadtest

# quantos usuários de carga existem (padrão carga-%@exemplo.com)
./scripts/contar-usuarios.sh

# contagem de uma execução específica
./scripts/contar-usuarios.sh --padrao 'carga-20261115T143000-%@exemplo.com'

# dry-run da limpeza
./scripts/limpar-usuarios.sh --prefixo carga-20261115T143000

# limpeza efetiva (remove também referências em entrada/saida_estoque)
./scripts/limpar-usuarios.sh --prefixo carga-20261115T143000 --yes
```

O `--prefixo` vem no rodapé do `rodar-carga.sh` e no arquivo
`usuarios.csv.prefixo` da execução. Por segurança, a limpeza só aceita padrões
terminados em `@exemplo.com`; um `--padrao` genérico precisa começar com
`carga-` (ou usar `--forcar`), e `--prefixo` é sempre validado por charset.

> A limpeza é **manual e deliberada**. O teste não apaga dados sozinho para que
> a contagem pós-teste possa ser usada como evidência.

---

## 9. Solução de problemas

| Sintoma | Causa provável | Ação |
|---|---|---|
| `alvo respondeu HTTP 000/502/503` | Stack indisponível ou ALB sem target saudável | `docker stack services megusta`; `curl -v <alb>/health`; verificar target group |
| `Nem JMeter local nem Docker` | Nem `jmeter` no PATH nem Docker | Instalar JMeter 5.5+ ou `docker pull justb4/jmeter:5.5` |
| `permission denied` ao rodar script | Falta bit de execução (scp do Windows) | `chmod +x scripts/*.sh` |
| `bad interpreter: /bin/bash^M` | CRLF | `../fix-eol.sh` no bastion |
| `409` no JTL | CSV reaproveitado | Gerar novo CSV/novo prefixo |
| `400` no JTL | Senha/telefone fora da validação | Usar o CSV do `gerar-usuarios.sh` |
| Cadastro para antes do fim | CSV esgotado (`recycle=false`) | Aumentar `--usuarios` |
| `No space left on device` | Muitos JTL/dashboards no bastion | Remover execuções antigas de `resultados/` |
| Container JMeter não escreve em `resultados/` | Permissão do volume | `--docker-user "$(id -u):$(id -g)"` (ou `JMETER_DOCKER_USER`) ou usar JMeter local |
| Consumer `0/2` | Contrato `MAIL_*` × `SMTP_*` | Ver seção do consumer no `../README.md` (mapeamento no compose) |
| `Could not resolve host: database` nos scripts de banco | Container cliente fora da rede do stack | Rode no manager do Swarm; confirme `docker network ls | grep megusta-net` |

---

## 10. Estrutura do diretório

```text
loadtest/
├── README.md
├── jmx/
│   └── megusta-carga.jmx        # plano com 3 grupos de threads
└── scripts/
    ├── gerar-usuarios.sh        # CSV único para o cadastro
    ├── rodar-carga.sh           # executa JMeter + análise
    ├── analisar-jtl.py          # métricas e critérios de aceite
    ├── contar-usuarios.sh       # SELECT COUNT(*) no MySQL do stack
    └── limpar-usuarios.sh       # DELETE seguro dos usuários de carga
```

Os resultados (`resultados/`) são gerados localmente e **não devem ser
commitados**.
