# MeGusta — Glue e Athena (Data Lake)

> **Documento de referência do que existe hoje.** Cobre tudo que está declarado em
> `Terraform-full/storage.tf`, `Terraform-full/lambda.tf` e `scripts/`, mais o passo a
> passo para executar cada peça.
>
> Região: **us-east-1**. Tudo abaixo roda com a role do laboratório
> (`var.glue_service_role_arn`, hoje `arn:aws:iam::<conta>:role/LabRole`).

---

## 1. Visão geral

```
                        ┌──────────────────────────────┐
   API REST do backend  │  Lambda megusta-export-estoque│
   (ALB interno :80) ◄──┤  python3.12, dentro da VPC    │
                        └───────────────┬──────────────┘
                                        │ CSV
                                        ▼
   Docker Swarm            ┌────────────────────────────┐
   (Fluent Bit em cada nó) │  s3://megusta-raw-us-east-1 │  camada RAW / Bronze
        JSON gzip ────────►│  /logs/...   /raw/megusta/...│
                            └───────────────┬────────────┘
                                            │ Glue Job
                                            ▼
                            ┌────────────────────────────┐
                            │ s3://megusta-trusted-...    │  camada TRUSTED / Silver
                            │  /project-data/  /logs/     │
                            └───────────────┬────────────┘
                                            │ Glue Job
                                            ▼
                            ┌────────────────────────────┐
                            │ s3://megusta-curated-...    │  camada CURATED / Gold
                            │  /vendas_*/  /athena-results│
                            └───────────────┬────────────┘
                                            │
                                            ▼
                              Athena workgroup megusta-analytics
                              Glue Data Catalog: megusta_datalake
```

---

## 2. Pré-requisitos

Os **3 buckets são criados manualmente** no console — a SCP do laboratório bloqueia
`s3:CreateBucket` via Terraform (`data "aws_s3_bucket"`, não `resource`):

| Bucket | Papel |
|---|---|
| `megusta-raw-us-east-1` | RAW/Bronze — CSVs da Lambda + logs do Fluent Bit |
| `megusta-trusted-us-east-1` | TRUSTED/Silver — Parquet limpo e particionado |
| `megusta-curated-us-east-1` | CURATED/Gold — agregações, scripts do Glue, `temp/` e `athena-results/` |

Cada bucket precisa de **versioning habilitado** e **criptografia AES256** (SSE-S3).

Outros pré-requisitos:

| Item | Como garantir |
|---|---|
| Role do Glue | `glue_service_role_arn` **tem default vazio e não há fallback automático** — se ficar vazio, crawler/job falham com `role` inválida. Defina o ARN no `terraform.tfvars`. |
| Credenciais da API | `api_login` (default `admin@megusta.com`) e `api_password` (sensitive) usadas pela Lambda no `POST /login`. |
| Backend no ar | A Lambda depende da API responder em `api_base_url` (ou no DNS do ALB, porta 80). |
| CLI da AWS | O bastion-a já vem com `awscli`. O instance profile (`LabInstanceProfile`) fornece as credenciais. |

---

## 3. Inventário (resumo)

| Tipo | Nome | Gatilho |
|---|---|---|
| Glue Data Catalog DB | `megusta_datalake` | criado pelo Terraform |
| Crawler | `megusta-raw-crawler` | `cron(0 6 * * ? *)` UTC |
| Crawler | `megusta-trusted-crawler` | `cron(0 8 * * ? *)` UTC |
| Crawler | `megusta-curated-crawler` | `cron(0 10 * * ? *)` UTC |
| Crawler | `megusta-logs-crawler` | `cron(0 */6 * * ? *)` UTC |
| Job Glue | `megusta-raw-to-trusted` | **manual** (sem trigger) |
| Job Glue | `megusta-trusted-to-curated` | **manual** (sem trigger) |
| Job Glue | `megusta-logs-bronze-to-silver` | **manual** (sem trigger) |
| Lambda | `megusta-export-estoque` | EventBridge `cron(0 3 * * ? *)` UTC (1×/dia) |
| Athena Workgroup | `megusta-analytics` | — |
| Athena Named Query | `megusta-logs-table` | manual (modelo de DDL) |
| Athena Named Query | `megusta-project-data-table` | manual (modelo de DDL) |
| Alarmes | 3× `megusta-glue-job-failed-<job>` | `glue.driver.aggregate.numFailedTasks > 0` → SNS |

> ⚠️ **Não existem Glue Triggers nem Workflows neste repositório.** Só os crawlers e a
> Lambda são agendados. Os 3 jobs precisam ser disparados manualmente (`start-job-run`)
> ou por um agendador externo que você criar (EventBridge → Lambda → `glue:StartJobRun`).

---

## 4. Layout no S3

```
s3://megusta-raw-us-east-1/
├── logs/<tag>/AAAA/MM/DD/HH/MMSS_<host>.log.gz     # Fluent Bit (gzip, um JSON por linha)
│     tags: docker | nginx.access | nginx.error | app.project
└── raw/megusta/<recurso>/ano=AAAA/mes=MM/dia=DD/<recurso>_<timestamp>.csv
      recursos: insumos | entradas-estoque | saidas-estoque | fornecedores

s3://megusta-trusted-us-east-1/
├── logs/year=.../month=.../day=.../hour=.../*.parquet # logs normalizados (gzip)
├── project-data/ano=<int>/mes=<int>/*.parquet      # dados de vendas (snappy)
└── vendas/ano=<int>/mes=<int>/*.parquet            # legado (CSV na raiz do raw)

s3://megusta-curated-us-east-1/
├── vendas_estado_mes/ano=.../mes=.../*.parquet
├── vendas_categoria_mes/ano=.../mes=.../*.parquet
├── vendas_cliente/estado=.../*.parquet
├── vendas_diaria/ano=.../mes=.../*.parquet
├── scripts/*.py                                    # scripts dos 3 jobs (upload pelo Terraform)
├── temp/                                           # --TempDir dos jobs
└── athena-results/                                 # resultados de query do workgroup
```

---

## 5. Ingestão

### 5.1 Lambda `megusta-export-estoque`

Arquivo: `scripts/export_megusta_estoque.py` (empacotado pelo `archive_file`).
Runtime `python3.12`, 256 MB, timeout 300 s, sem dependências externas (stdlib + boto3).

**Fluxo:** `POST /login` (email/senha) → JWT → `GET /<recurso>` para cada item de
`RECURSOS` → achata objetos aninhados (`insumo.nome` → `insumo_nome`, listas viram
JSON) → grava **um CSV por recurso** no S3.

**Variáveis de ambiente:**

| Variável | Default | Observação |
|---|---|---|
| `RAW_BUCKET` | — | `megusta-raw-us-east-1` |
| `API_BASE_URL` | `http://<alb-dns>` | `var.api_base_url`; se vazio usa o ALB na porta 80 |
| `API_LOGIN` / `API_PASSWORD` | `admin@megusta.com` / sensitive | devem ser de um usuário real do banco |
| `RAW_PREFIX` | `raw/megusta` | prefixo das partições |
| `RECURSOS` | `insumos,entradas-estoque,saidas-estoque,fornecedores` | separado por vírgula |

**Rede:** roda nas subnets privadas com o SG `lambda-sg` (só egress). Alcança a API pelo
ALB interno graças à regra `backend-sg` → `lambda-sg:8080`. Sai para o S3 pelo NAT.

**Comportamento em erro:** falha no login aborta tudo (`status: erro`); falha em um
recurso não impede os demais (é reportada no resumo do retorno).

### 5.2 Fluent Bit (logs)

Cada instância EC2 roda Fluent Bit (instalado pelo `user_data`) com output S3:

- bucket RAW, `s3_key_format /logs/$TAG/%Y/%m/%d/%H/%M/%S_<host>.log`, gzip, 50 MB por arquivo
- inputs: `docker`, `nginx.access`, `nginx.error`, `app.project` (`/var/log/megusta/*.log`, parser JSON)
- credenciais vêm do instance profile (sem chave no arquivo)
- também há output para CloudWatch Logs, em `/aws/ec2/megusta/fluent-bit` (os grupos
  `/aws/ec2/megusta/{nginx,docker,system}` são criados em `monitoring.tf`)

---

## 6. Glue Data Catalog

Database: **`megusta_datalake`**.

| Tabela | Quem cria | Formato | Partições |
|---|---|---|---|
| `project_data_trusted` | job `raw-to-trusted` | Parquet/snappy | `ano`, `mes` |
| `vendas_trusted` | job `raw-to-trusted` (legado) | Parquet/snappy | `ano`, `mes` |
| `logs_silver` | job `logs-bronze-to-silver` | Parquet/gzip | `year`, `month`, `day`, `hour` |
| `vendas_estado_mes` | job `trusted-to-curated` | Parquet | `ano`, `mes` |
| `vendas_categoria_mes` | job `trusted-to-curated` | Parquet | `ano`, `mes` |
| `vendas_cliente` | job `trusted-to-curated` | Parquet | `estado` |
| `vendas_diaria` | job `trusted-to-curated` | Parquet | `ano`, `mes` |
| tabelas do RAW | crawler `megusta-raw-crawler` | inferido | inferido |

Os jobs criam as tabelas via `spark.sql("CREATE EXTERNAL TABLE IF NOT EXISTS ...")` e
rodam `MSCK REPAIR TABLE` para registrar as partições. Se a tabela já existir, o
comando é um no-op — o schema **não** é alterado.

As tabelas geradas pelo crawler RAW recebem nomes automáticos (derivados do prefixo).
Descubra os nomes com:

```sql
SHOW TABLES IN megusta_datalake;
```

---

## 7. Crawlers

Todos usam `local.glue_role_arn`, database `megusta_datalake` e
`CrawlerOutput.Partitions.AddOrUpdateBehavior = InheritFromTable`.

| Crawler | Alvo | Schedule (UTC) | Extra |
|---|---|---|---|
| `megusta-raw-crawler` | `s3://megusta-raw-us-east-1/` | `0 6 * * ? *` | cataloga o bucket inteiro |
| `megusta-trusted-crawler` | `s3://megusta-trusted-us-east-1/` | `0 8 * * ? *` | |
| `megusta-curated-crawler` | `s3://megusta-curated-us-east-1/` | `0 10 * * ? *` | |
| `megusta-logs-crawler` | `s3://megusta-raw-us-east-1/logs/` | `0 */6 * * ? *` | `CombineCompatibleSchemas` |

Ordem diária: Lambda 03:00 → raw 06:00 → trusted 08:00 → curated 10:00.

> ⚠️ `megusta-logs-crawler` aponta para `s3://.../logs/` do bucket **RAW**, não para o
> `trusted/logs/`. Quem cria a tabela `logs_silver` é o **job** (via `CREATE EXTERNAL
> TABLE`), não o crawler. O `trusted-crawler` cobre o bucket trusted inteiro e pode
> catalogar `trusted/logs/` como tabela extra — se isso acontecer, ignore a duplicata.

**Executar agora:**

```bash
aws glue start-crawler --name megusta-raw-crawler --region us-east-1

# acompanhar (State: READY | RUNNING | STOPPING)
aws glue get-crawler --name megusta-raw-crawler --region us-east-1 \
  --query 'Crawler.[State,LastCrawl.Status,LastCrawl.ErrorMessage]' --output table
```

---

## 8. Jobs Glue

Todos: `glueetl`, `python_version=3`, `glue_version=4.0`, `max_retries=0`,
`--enable-continuous-cloudwatch-log=true`, `--enable-metrics=true`,
`--TempDir=s3://megusta-curated-us-east-1/temp/`.
O script fica em `s3://megusta-curated-us-east-1/scripts/` e é enviado pelo Terraform
(`aws_s3_object` + `etag = filemd5(...)` — alterar o `.py` e rodar `apply` atualiza o S3).

| Job | Workers | Timeout | Args próprios |
|---|---|---|---|
| `megusta-raw-to-trusted` | 2× G.1X | 120 min | `RAW_BUCKET`, `TRUSTED_BUCKET`, `DATABASE_NAME`, `RAW_PROJECT_PREFIX=project-data/` |
| `megusta-trusted-to-curated` | 4× G.1X | 180 min | `TRUSTED_BUCKET`, `CURATED_BUCKET`, `DATABASE_NAME` |
| `megusta-logs-bronze-to-silver` | 2× G.1X | 120 min | `RAW_BUCKET`, `TRUSTED_BUCKET`, `DATABASE_NAME`, `LOGS_PREFIX=logs/` |

### 8.1 `megusta-raw-to-trusted` — `scripts/raw_to_trusted.py`

1. Lê `s3://<raw>/project-data/` como CSV (`header=true`, `inferSchema=true`).
2. Limpa: remove duplicatas, exige `id_pedido`, faz `trim`/`upper`, converte
   `data_compra` para `DATE`, `valor` para `DECIMAL(10,2)`, `quantidade` para `INT`,
   descarta `valor <= 0`, `quantidade <= 0` e data nula.
3. Deriva `ano`, `mes`, `dia`.
4. Escreve `s3://<trusted>/project-data/` em Parquet/snappy, `partitionBy(ano, mes)`,
   **`mode("overwrite")`** (reprocessa tudo).
5. Cria `megusta_datalake.project_data_trusted` e roda `MSCK REPAIR`.
6. Se não houver dados, cria a tabela vazia com o schema esperado (não falha).
7. **Legado:** tenta ler CSVs na raiz do bucket RAW e, se houver, grava
   `s3://<trusted>/vendas/` + tabela `vendas_trusted`. Erros aqui são apenas logados.

### 8.2 `megusta-trusted-to-curated` — `scripts/trusted_to_curated.py`

Lê `s3://<trusted>/project-data/` (Parquet) e gera 4 agregações, todas `mode("overwrite")`:

| Tabela | Grão | Métricas |
|---|---|---|
| `vendas_estado_mes` | estado + ano/mês | pedidos, receita, itens, ticket médio, itens/pedido |
| `vendas_categoria_mes` | categoria + ano/mês | pedidos, receita, itens, ticket médio |
| `vendas_cliente` | cliente + estado | pedidos, valor total, itens, ticket médio, 1ª e última compra |
| `vendas_diaria` | data + ano/mês | pedidos, receita, itens, clientes únicos |

Depois cria as 4 tabelas externas e roda `MSCK REPAIR`.

> ⚠️ Este job **não tem tratamento de erro**: se `trusted/project-data/` não existir
> (porque o job anterior não rodou), ele falha. Respeite a ordem.

### 8.3 `megusta-logs-bronze-to-silver` — `scripts/logs_bronze_to_silver.py`

1. Lê `s3://<raw>/logs/` como JSON Lines (formato do Fluent Bit).
2. Extrai `year/month/day/hour/log_type` do **caminho** do arquivo
   (`logs/<tag>/AAAA/MM/DD/HH/...`).
3. Normaliza nomes de campo alternativos (`time`/`@timestamp`, `level`/`severity`/`log_level`,
   `message`/`log`/`msg`, etc.), remove nulos em `timestamp`/`message` e duplicatas.
4. Escreve `s3://<trusted>/logs/` em Parquet/gzip, `partitionBy(year, month, day, hour)`,
   **`mode("append")`**.
5. Cria `logs_silver` e roda `MSCK REPAIR`.

> ⚠️ Como é `append`, rodar o job duas vezes sobre o mesmo período pode duplicar
> registros (o `dropDuplicates` só vale dentro do próprio batch).

### 8.4 Executar um job

```bash
# disparar
aws glue start-job-run --job-name megusta-raw-to-trusted --region us-east-1 \
  --query 'JobRunId' --output text

# acompanhar (substitua o ID)
aws glue get-job-run --job-name megusta-raw-to-trusted --run-id jr_xxxxxxxx \
  --region us-east-1 \
  --query 'JobRun.[JobRunState,ErrorMessage,ExecutionTime]' --output table
```

Estados: `STARTING → RUNNING → SUCCEEDED | FAILED | TIMEOUT | STOPPED`.

Logs:

```bash
# log clássico do driver
aws logs tail /aws-glue/jobs/output --follow --region us-east-1

# se existir, o log contínuo (habilitado nos 3 jobs)
aws logs tail /aws-glue/jobs/logs-v2 --follow --region us-east-1
```

Também é possível rodar pelo console: **Glue → ETL jobs → selecionar → Run**.

---

## 9. Athena

### 9.1 Workgroup

| Config | Valor |
|---|---|
| Nome | `megusta-analytics` |
| `enforce_workgroup_configuration` | `true` (configurações do cliente são ignoradas) |
| `bytes_scanned_cutoff_per_query` | **10 GiB** (query acima disso é cancelada) |
| Resultados | `s3://megusta-curated-us-east-1/athena-results/` |
| Criptografia dos resultados | `SSE_S3` |
| Métricas | publicadas no CloudWatch |

Como a configuração é enforced, **não é preciso** passar `--result-configuration` na CLI.

### 9.2 Named queries (modelos de DDL)

Criadas pelo Terraform, mas **não executadas automaticamente**. São consultas salvas
que você roda uma vez se quiser que o Athena crie a tabela:

| Nome | Tabela | Formato declarado |
|---|---|---|
| `megusta-logs-table` | `logs_silver` | CSV + `LazySimpleSerDe`, gzip, projeção `year/month/day/hour` |
| `megusta-project-data-table` | `project_data_trusted` | Parquet/snappy, projeção `ano/mes` |

> ⚠️ **Divergência conhecida:** o named query `megusta-logs-table` declara **CSV**, mas o
> job `logs-bronze-to-silver` grava **Parquet** e cria a tabela como `STORED AS PARQUET`.
> Como os dois usam `IF NOT EXISTS`, **quem rodar primeiro vence**. Recomendação: rode o
> job primeiro e trate o named query como legado; ou alinhe o named query para Parquet
> antes de usá-lo em um ambiente novo.

### 9.3 Rodar no console

1. Athena → Workgroup `megusta-analytics`.
2. Database `megusta_datalake`.
3. Cole a query e execute. Os resultados aparecem no painel e ficam em
   `s3://megusta-curated-us-east-1/athena-results/`.
4. Para usar um modelo salvo: aba **Saved queries** → selecionar → **Run**.

### 9.4 Rodar pela CLI

```bash
# 1) inicia a query
QID=$(aws athena start-query-execution \
  --work-group megusta-analytics \
  --query-string "SELECT * FROM megusta_datalake.project_data_trusted LIMIT 10" \
  --region us-east-1 --query 'QueryExecutionId' --output text)

# 2) aguarda/consulta o estado
aws athena get-query-execution --query-execution-id "$QID" --region us-east-1 \
  --query 'QueryExecution.Status.[State,StateChangeReason]' --output table

# 3) pega o resultado (CSV em JSON)
aws athena get-query-results --query-execution-id "$QID" --region us-east-1
```

Listar e executar um named query:

```bash
aws athena list-named-queries --region us-east-1
aws athena get-named-query --named-query-id <ID> --region us-east-1 \
  --query 'NamedQuery.QueryString' --output text
```

### 9.5 Consultas úteis

```sql
-- conferir partições registradas
SHOW PARTITIONS megusta_datalake.logs_silver;

-- se gravou dados novos sem passar pelo job
MSCK REPAIR TABLE megusta_datalake.logs_silver;

-- volume de logs por nível nas últimas 24 h
SELECT level, count(*) AS total
FROM megusta_datalake.logs_silver
WHERE year = '2026' AND month = '11' AND day = '04'
GROUP BY level
ORDER BY total DESC;

-- erros recentes por container
SELECT container_name, count(*) AS erros
FROM megusta_datalake.logs_silver
WHERE level IN ('ERROR', 'FATAL')
  AND year = '2026' AND month = '11'
GROUP BY container_name
ORDER BY erros DESC;

-- top estados por receita
SELECT estado, sum(receita_total) AS receita
FROM megusta_datalake.vendas_estado_mes
GROUP BY estado
ORDER BY receita DESC;

-- clientes com maior valor
SELECT id_cliente, valor_total_cliente, total_pedidos
FROM megusta_datalake.vendas_cliente
ORDER BY valor_total_cliente DESC
LIMIT 20;
```

> As partições de `logs_silver` são `string` (`year='2026'`), enquanto as de
> `project_data_trusted`/`vendas_*` são `int` (`ano=2026`). Use aspas só nas primeiras.

---

## 10. Monitoramento

| Recurso | O que faz |
|---|---|
| Dashboard `megusta-infrastructure` | inclui `glue.driver.aggregate.numCompletedTasks` e `numFailedTasks` dos 3 jobs |
| Alarme `megusta-glue-job-failed-<job>` | `numFailedTasks > 0` por 1 período (5 min) → SNS `alerts` |
| SNS `alerts` | assinatura de e-mail em `var.sns_email` (**precisa confirmar o clique**) |
| CloudWatch Logs | `/aws-glue/jobs/output`, `/aws-glue/jobs/logs-v2`, `/aws/lambda/megusta-export-estoque` (retenção 14 dias), `/aws/ec2/megusta/*` (30 dias) |

O alarme usa `treat_missing_data = "missing"`, então ele não dispara em períodos sem
execução — só quando o job roda e falha.

---

## 11. Passo a passo completo

### 11.1 Provisionar (LOCAL, na sua máquina)

```bash
cd Terraform-full
# terraform.tfvars precisa ter:
#   glue_service_role_arn = "arn:aws:iam::<conta>:role/LabRole"
#   api_password          = "<senha real>"
tofu init
tofu plan
tofu apply
```

Confira os nomes gerados:

```bash
tofu output
```

Saídas relevantes: `glue_database_name`, `glue_*_crawler_name`, `glue_*_job_name`,
`athena_workgroup_name`, `athena_results_location`, `athena_query_role_arn`,
`lambda_export_function_name`.

### 11.2 Validar a Lambda isoladamente

```bash
aws lambda invoke --function-name megusta-export-estoque \
  --payload '{}' --region us-east-1 /tmp/lambda-out.json
cat /tmp/lambda-out.json

aws s3 ls s3://megusta-raw-us-east-1/raw/megusta/insumos/ --recursive
```

Esperado: um CSV por recurso, no caminho
`raw/megusta/<recurso>/ano=AAAA/mes=MM/dia=DD/`.

### 11.3 Rodar o pipeline de logs

```bash
aws glue start-job-run --job-name megusta-logs-bronze-to-silver --region us-east-1
# acompanhar com get-job-run (seção 8.4)
aws s3 ls s3://megusta-trusted-us-east-1/logs/ --recursive | head -5
```

### 11.4 Rodar o pipeline de vendas (na ordem)

```bash
aws glue start-job-run --job-name megusta-raw-to-trusted --region us-east-1
# aguardar SUCCEEDED
aws glue start-job-run --job-name megusta-trusted-to-curated --region us-east-1
```

### 11.5 Catalogar e consultar

```bash
aws glue start-crawler --name megusta-trusted-crawler --region us-east-1
# quando o crawler voltar a READY, consulte:
aws athena list-named-queries --region us-east-1
```

Ou, no console: Athena → `megusta-analytics` → `megusta_datalake` → `SHOW TABLES`.

### 11.6 Parar um job em execução

```bash
aws glue batch-stop-job-run --job-name megusta-logs-bronze-to-silver \
  --job-run-ids jr_xxxxxxxx --region us-east-1
```

---

## 12. Divergências conhecidas (leia antes de confiar no pipeline)

| # | Problema | Impacto | Correção sugerida |
|---|---|---|---|
| 1 | A Lambda grava em `raw/megusta/<recurso>/...`, mas `raw-to-trusted` lê `raw/project-data/` (`RAW_PROJECT_PREFIX`) | Os CSVs de **estoque** não entram em `project_data_trusted`. Ficam só no RAW, catalogados pelo `megusta-raw-crawler`. | Alinhar `RAW_PROJECT_PREFIX` com `raw_prefix` **e** adaptar o script (o schema do estoque não tem `id_pedido`/`valor`/`quantidade`). |
| 2 | O named query `megusta-logs-table` declara CSV; o job grava Parquet | Se o named query rodar primeiro, o Athena lê Parquet como CSV e falha. | Rodar o job primeiro ou trocar o named query para `STORED AS PARQUET`. |
| 3 | `glue_service_role_arn` tem default `""` e não há fallback para o `LabInstanceProfile` | Crawlers/jobs falham se a variável não for preenchida. | Sempre definir o ARN no `terraform.tfvars`. |
| 4 | Nenhum Glue Trigger/Workflow | Os jobs só rodam se alguém chamar `start-job-run`. | Criar EventBridge + Lambda ou `aws_glue_trigger` condicionado ao sucesso do job anterior. |
| 5 | `raw-to-trusted` lê a **raiz** do bucket RAW no bloco "legado" (inclui `logs/` e `raw/megusta/`) | Pode falhar/lixo no bloco legado (erro é engolido pelo `try/except`). | Restringir o caminho legado a um prefixo específico. |
| 6 | `logs-bronze-to-silver` usa `append` | Reprocessar o mesmo período duplica linhas. | Usar `overwrite` por partição ou deduplicar por `timestamp + container + message`. |
| 7 | Athena com corte de 10 GiB/query | Queries amplas em `logs_silver` são canceladas. | Sempre filtrar por `year/month/day`. |
| 8 | Assinatura SNS por e-mail | Sem confirmar o clique, nenhum alarme chega. | Confirmar em `sns_email`. |

---

## 13. Referência: variáveis e outputs

### Variáveis (`Terraform-full/variables.tf`)

| Variável | Default | Usada por |
|---|---|---|
| `glue_service_role_arn` | `""` | crawlers, jobs, Lambda |
| `api_base_url` | `""` (ALB DNS) | Lambda |
| `api_login` | `admin@megusta.com` | Lambda |
| `api_password` | `sensitive`, default `sptech` | Lambda |
| `raw_prefix` | `raw/megusta` | Lambda |
| `lambda_recursos` | `insumos,entradas-estoque,saidas-estoque,fornecedores` | Lambda |
| `lambda_timeout` | `300` | Lambda |
| `lambda_memory_size` | `256` | Lambda |
| `lambda_schedule_enabled` | `true` | EventBridge |
| `lambda_schedule_expression` | `cron(0 3 * * ? *)` | EventBridge |
| `lambda_log_retention_days` | `14` | CloudWatch Logs |
| `sns_email` | `henry.silva@sptech.school` | SNS dos alarmes |

### Outputs (`Terraform-full/outputs.tf`)

`glue_database_name`, `glue_service_role_arn`, `glue_raw_crawler_name`,
`glue_trusted_crawler_name`, `glue_curated_crawler_name`, `glue_logs_crawler_name`,
`glue_raw_to_trusted_job_name`, `glue_trusted_to_curated_job_name`,
`glue_logs_bronze_to_silver_job_name`, `athena_workgroup_name`,
`athena_results_location`, `athena_query_role_arn`, `lambda_export_function_name`,
`lambda_export_function_arn`, `sns_topic_arn`.

---

## 14. Custos e limpeza

- **Glue jobs**: cobrados por DPU-hora. `raw-to-trusted` e `logs-bronze-to-silver` usam
  2 workers G.1X; `trusted-to-curated` usa 4. Como não há trigger, só gastam quando você
  dispara.
- **Crawlers**: cobrados por DPU-hora enquanto rodam; os 4 agendamentos diários somam
  pouco, mas rodam mesmo sem dado novo.
- **Athena**: cobrado por byte escaneado (US$ 5/TB). O corte de 10 GiB limita uma query
  a ~US$ 0,05.
- **S3**: 3 buckets com versioning — atenção a `raw/logs/` e ao lixo de `temp/`.

Para desligar o pipeline sem destruir a infra:

```bash
aws events disable-rule --name megusta-export-estoque-schedule --region us-east-1
# e remova os schedules dos crawlers (ou destrua via tofu)
```

Para remover tudo que este documento descreve:

```bash
cd Terraform-full
tofu destroy -target=aws_glue_job.raw_to_trusted \
             -target=aws_glue_job.trusted_to_curated \
             -target=aws_glue_job.logs_bronze_to_silver \
             -target=aws_glue_crawler.raw_crawler \
             -target=aws_glue_crawler.trusted_crawler \
             -target=aws_glue_crawler.curated_crawler \
             -target=aws_glue_crawler.logs_crawler
```

> Os buckets **não** são destruídos (são `data sources`), e os dados continuam lá.
