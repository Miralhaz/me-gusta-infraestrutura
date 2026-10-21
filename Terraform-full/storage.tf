# ==========================================
# S3 BUCKETS - USANDO DATA SOURCES (SCP bloqueia criação via Terraform)
# ==========================================
# CRIE OS 3 BUCKETS MANUALMENTE NO CONSOLE ANTES DO APPLY:
#   megusta-raw-us-east-1
#   megusta-trusted-us-east-1
#   megusta-curated-us-east-1
#
# Com versioning habilitado e criptografia AES256.
# Depois rode: tofu apply ...

data "aws_s3_bucket" "raw" {
  bucket = "megusta-raw-us-east-1"
}

data "aws_s3_bucket" "trusted" {
  bucket = "megusta-trusted-us-east-1"
}

data "aws_s3_bucket" "curated" {
  bucket = "megusta-curated-us-east-1"
}

# ==========================================
# GLUE DATA CATALOG DATABASE
# ==========================================
resource "aws_glue_catalog_database" "megusta" {
  name        = "megusta_datalake"
  description = "Data Catalog database para o Data Lake MeGusta (raw, trusted, curated)"
}

# ==========================================
# GLUE SERVICE ROLE
# ==========================================
# Usa a role fornecida via variável (ex: LabRole existente).
# NÃO tenta criar role (evita erro iam:CreateRole).
locals {
  glue_role_arn = var.glue_service_role_arn
}

# ==========================================
# GLUE CRAWLERS
# ==========================================
resource "aws_glue_crawler" "raw_crawler" {
  name          = "megusta-raw-crawler"
  role          = local.glue_role_arn
  database_name = aws_glue_catalog_database.megusta.name

  schedule = "cron(0 6 * * ? *)"

  s3_target {
    path = "s3://${data.aws_s3_bucket.raw.bucket}/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = {
    Layer = "raw"
  }
}

resource "aws_glue_crawler" "trusted_crawler" {
  name          = "megusta-trusted-crawler"
  role          = local.glue_role_arn
  database_name = aws_glue_catalog_database.megusta.name

  schedule = "cron(0 8 * * ? *)"

  s3_target {
    path = "s3://${data.aws_s3_bucket.trusted.bucket}/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = {
    Layer = "trusted"
  }
}

resource "aws_glue_crawler" "curated_crawler" {
  name          = "megusta-curated-crawler"
  role          = local.glue_role_arn
  database_name = aws_glue_catalog_database.megusta.name

  schedule = "cron(0 10 * * ? *)"

  s3_target {
    path = "s3://${data.aws_s3_bucket.curated.bucket}/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = {
    Layer = "curated"
  }
}

# ==========================================
# GLUE CRAWLER FOR LOGS (Bronze -> Silver)
# ==========================================
resource "aws_glue_crawler" "logs_crawler" {
  name          = "megusta-logs-crawler"
  role          = local.glue_role_arn
  database_name = aws_glue_catalog_database.megusta.name

  schedule = "cron(0 */6 * * ? *)"

  s3_target {
    path = "s3://${data.aws_s3_bucket.raw.bucket}/logs/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = {
    Layer = "logs"
  }
}

# ==========================================
# GLUE ETL JOBS
# ==========================================
resource "aws_glue_job" "raw_to_trusted" {
  name     = "megusta-raw-to-trusted"
  role_arn = local.glue_role_arn

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.curated.bucket}/scripts/raw_to_trusted.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${data.aws_s3_bucket.curated.bucket}/temp/"
    "--RAW_BUCKET"                       = data.aws_s3_bucket.raw.bucket
    "--TRUSTED_BUCKET"                   = data.aws_s3_bucket.trusted.bucket
    "--DATABASE_NAME"                    = aws_glue_catalog_database.megusta.name
    "--RAW_PROJECT_PREFIX"               = "project-data/"
  }

  max_retries       = 0
  timeout           = 120
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  tags = {
    Pipeline = "raw-to-trusted"
  }
}

resource "aws_glue_job" "trusted_to_curated" {
  name     = "megusta-trusted-to-curated"
  role_arn = local.glue_role_arn

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.curated.bucket}/scripts/trusted_to_curated.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${data.aws_s3_bucket.curated.bucket}/temp/"
    "--TRUSTED_BUCKET"                   = data.aws_s3_bucket.trusted.bucket
    "--CURATED_BUCKET"                   = data.aws_s3_bucket.curated.bucket
    "--DATABASE_NAME"                    = aws_glue_catalog_database.megusta.name
  }

  max_retries       = 0
  timeout           = 180
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 4

  tags = {
    Pipeline = "trusted-to-curated"
  }
}

resource "aws_glue_job" "logs_bronze_to_silver" {
  name     = "megusta-logs-bronze-to-silver"
  role_arn = local.glue_role_arn

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.curated.bucket}/scripts/logs_bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"     = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${data.aws_s3_bucket.curated.bucket}/temp/"
    "--RAW_BUCKET"                       = data.aws_s3_bucket.raw.bucket
    "--TRUSTED_BUCKET"                   = data.aws_s3_bucket.trusted.bucket
    "--DATABASE_NAME"                    = aws_glue_catalog_database.megusta.name
    "--LOGS_PREFIX"                      = "logs/"
  }

  max_retries       = 0
  timeout           = 120
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  tags = {
    Pipeline = "logs-bronze-to-silver"
  }
}

# ==========================================
# ATHENA WORKGROUP
# ==========================================
resource "aws_athena_workgroup" "megusta" {
  name = "megusta-analytics"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 10737418240

    result_configuration {
      output_location = "s3://${data.aws_s3_bucket.curated.bucket}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = {
    Environment = "prod"
    Purpose     = "analytics"
  }
}

# ==========================================
# S3 OBJECTS FOR GLUE SCRIPTS
# ==========================================
resource "aws_s3_object" "raw_to_trusted_script" {
  bucket = data.aws_s3_bucket.curated.bucket
  key    = "scripts/raw_to_trusted.py"
  source = "../scripts/raw_to_trusted.py"
  etag   = filemd5("../scripts/raw_to_trusted.py")
}

resource "aws_s3_object" "trusted_to_curated_script" {
  bucket = data.aws_s3_bucket.curated.bucket
  key    = "scripts/trusted_to_curated.py"
  source = "../scripts/trusted_to_curated.py"
  etag   = filemd5("../scripts/trusted_to_curated.py")
}

resource "aws_s3_object" "logs_bronze_to_silver_script" {
  bucket = data.aws_s3_bucket.curated.bucket
  key    = "scripts/logs_bronze_to_silver.py"
  source = "../scripts/logs_bronze_to_silver.py"
  etag   = filemd5("../scripts/logs_bronze_to_silver.py")
}

# ==========================================
# ATHENA TABLE FOR LOGS (Silver/Trusted layer)
# ==========================================
resource "aws_athena_named_query" "logs_table" {
  name        = "megusta-logs-table"
  database    = aws_glue_catalog_database.megusta.name
  workgroup   = aws_athena_workgroup.megusta.name
  description = "Tabela Athena para logs de aplicacao, nginx e sistema (camada trusted/silver)"

  query = <<-SQL
    CREATE EXTERNAL TABLE IF NOT EXISTS ${aws_glue_catalog_database.megusta.name}.logs_silver (
      timestamp string,
      level string,
      message string,
      source string,
      container_id string,
      container_name string,
      host string,
      log_type string
    )
    PARTITIONED BY (
      year string,
      month string,
      day string,
      hour string
    )
    ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
    WITH SERDEPROPERTIES (
      'serialization.format' = ',',
      'field.delim' = ','
    )
    LOCATION 's3://${data.aws_s3_bucket.trusted.bucket}/logs/'
    TBLPROPERTIES (
      'has_encrypted_data'='false',
      'compressionType'='gzip',
      'projection.enabled'='true',
      'projection.year.type'='integer',
      'projection.year.range'='2024,2030',
      'projection.month.type'='integer',
      'projection.month.range'='1,12',
      'projection.month.digits'='2',
      'projection.day.type'='integer',
      'projection.day.range'='1,31',
      'projection.day.digits'='2',
      'projection.hour.type'='integer',
      'projection.hour.range'='0,23',
      'projection.hour.digits'='2',
      'storage.location.template'='s3://${data.aws_s3_bucket.trusted.bucket}/logs/$${year}/$${month}/$${day}/$${hour}/'
    );
  SQL
}

# ==========================================
# ATHENA TABLE FOR PROJECT DATA (Trusted layer)
# ==========================================
resource "aws_athena_named_query" "project_data_table" {
  name        = "megusta-project-data-table"
  database    = aws_glue_catalog_database.megusta.name
  workgroup   = aws_athena_workgroup.megusta.name
  description = "Tabela Athena para dados do projeto (pedidos, produtos, clientes) na camada trusted"

  query = <<-SQL
    CREATE EXTERNAL TABLE IF NOT EXISTS ${aws_glue_catalog_database.megusta.name}.project_data_trusted (
      id_pedido string,
      id_cliente string,
      estado string,
      categoria string,
      data_compra date,
      valor decimal(10,2),
      quantidade int,
      dia int
    )
    PARTITIONED BY (ano int, mes int)
    STORED AS PARQUET
    LOCATION 's3://${data.aws_s3_bucket.trusted.bucket}/project-data/'
    TBLPROPERTIES (
      'has_encrypted_data'='false',
      'compressionType'='snappy',
      'projection.enabled'='true',
      'projection.ano.type'='integer',
      'projection.ano.range'='2024,2030',
      'projection.mes.type'='integer',
      'projection.mes.range'='1,12',
      'projection.mes.digits'='2',
      'storage.location.template'='s3://${data.aws_s3_bucket.trusted.bucket}/project-data/ano=$${ano}/mes=$${mes}/'
    );
  SQL
}