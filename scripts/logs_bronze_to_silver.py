import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, to_timestamp, year, month, dayofmonth, hour, regexp_extract, when, isnan, isnull, trim, input_file_name
from pyspark.sql.types import StringType, TimestampType

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'RAW_BUCKET',
    'TRUSTED_BUCKET',
    'DATABASE_NAME',
    'LOGS_PREFIX'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

raw_bucket = args['RAW_BUCKET']
trusted_bucket = args['TRUSTED_BUCKET']
database_name = args['DATABASE_NAME']
logs_prefix = args['LOGS_PREFIX']

print(f"Iniciando job LOGS BRONZE -> SILVER")
print(f"Raw bucket: s3://{raw_bucket}")
print(f"Trusted bucket: s3://{trusted_bucket}")
print(f"Database: {database_name}")
print(f"Logs prefix: {logs_prefix}")

# Ler logs da camada BRONZE (raw)
# Os logs vêm do Fluent Bit em formato JSON Lines (um JSON por linha)
raw_path = f"s3://{raw_bucket}/{logs_prefix}"

try:
    df_raw = spark.read.json(raw_path)
    print(f"Registros lidos do BRONZE: {df_raw.count()}")
    print(f"Colunas: {df_raw.columns}")
except Exception as e:
    print(f"Erro ao ler logs do BRONZE: {e}")
    print("Nenhum log encontrado ou formato inválido. Criando tabela vazia.")
    # Criar DataFrame vazio com schema esperado
    from pyspark.sql.types import StructType, StructField, StringType, TimestampType
    empty_schema = StructType([
        StructField("timestamp", StringType(), True),
        StructField("level", StringType(), True),
        StructField("message", StringType(), True),
        StructField("source", StringType(), True),
        StructField("container_id", StringType(), True),
        StructField("container_name", StringType(), True),
        StructField("host", StringType(), True),
        StructField("log_type", StringType(), True),
        StructField("year", StringType(), True),
        StructField("month", StringType(), True),
        StructField("day", StringType(), True),
        StructField("hour", StringType(), True)
    ])
    df_raw = spark.createDataFrame([], empty_schema)

if df_raw.count() > 0:
    # Extrair informações do caminho do arquivo para particionamento
    df_with_path = df_raw.withColumn("file_path", input_file_name())
    
    # Extrair partições do caminho S3: s3://bucket/logs/docker.xxx/2024/12/01/10/...
    df_parsed = df_with_path \
        .withColumn("year", regexp_extract(col("file_path"), r"logs/[^/]+/(\d{4})/", 1)) \
        .withColumn("month", regexp_extract(col("file_path"), r"logs/[^/]+/\d{4}/(\d{2})/", 1)) \
        .withColumn("day", regexp_extract(col("file_path"), r"logs/[^/]+/\d{4}/\d{2}/(\d{2})/", 1)) \
        .withColumn("hour", regexp_extract(col("file_path"), r"logs/[^/]+/\d{4}/\d{2}/\d{2}/(\d{2})/", 1)) \
        .withColumn("log_type", regexp_extract(col("file_path"), r"logs/([^/]+)/", 1))
    
    # Normalizar campos comuns dos logs
    df_silver = df_parsed \
        .withColumn("timestamp", 
            when(col("time").isNotNull(), col("time"))
            .when(col("@timestamp").isNotNull(), col("@timestamp"))
            .when(col("timestamp").isNotNull(), col("timestamp"))
            .otherwise(None)
        ) \
        .withColumn("level",
            when(col("level").isNotNull(), trim(col("level")))
            .when(col("severity").isNotNull(), trim(col("severity")))
            .when(col("log_level").isNotNull(), trim(col("log_level")))
            .otherwise("INFO")
        ) \
        .withColumn("message",
            when(col("message").isNotNull(), trim(col("message")))
            .when(col("log").isNotNull(), trim(col("log")))
            .when(col("msg").isNotNull(), trim(col("msg")))
            .otherwise("")
        ) \
        .withColumn("source",
            when(col("source").isNotNull(), trim(col("source")))
            .when(col("logger").isNotNull(), trim(col("logger")))
            .otherwise(col("log_type"))
        ) \
        .withColumn("container_id",
            when(col("container_id").isNotNull(), trim(col("container_id")))
            .when(col("container_id_full").isNotNull(), trim(col("container_id_full")))
            .otherwise("")
        ) \
        .withColumn("container_name",
            when(col("container_name").isNotNull(), trim(col("container_name")))
            .when(col("kubernetes_container_name").isNotNull(), trim(col("kubernetes_container_name")))
            .otherwise("")
        ) \
        .withColumn("host",
            when(col("host").isNotNull(), trim(col("host")))
            .when(col("hostname").isNotNull(), trim(col("hostname")))
            .otherwise("")
        ) \
        .select(
            "timestamp", "level", "message", "source",
            "container_id", "container_name", "host", "log_type",
            "year", "month", "day", "hour"
        ) \
        .filter(col("timestamp").isNotNull()) \
        .filter(col("message").isNotNull()) \
        .dropDuplicates()
    
    print(f"Registros após processamento: {df_silver.count()}")
    
    # Escrever na camada SILVER (trusted) como Parquet particionado
    trusted_path = f"s3://{trusted_bucket}/logs/"
    df_silver.write \
        .mode("append") \
        .partitionBy("year", "month", "day", "hour") \
        .parquet(trusted_path, compression="gzip")
    
    print(f"Dados gravados em: {trusted_path}")
    
    # Atualizar tabela no Glue Data Catalog
    df_silver.createOrReplaceTempView("logs_silver")
    spark.sql(f"""
        CREATE DATABASE IF NOT EXISTS {database_name}
    """)
    
    spark.sql(f"""
        CREATE EXTERNAL TABLE IF NOT EXISTS {database_name}.logs_silver (
            timestamp STRING,
            level STRING,
            message STRING,
            source STRING,
            container_id STRING,
            container_name STRING,
            host STRING,
            log_type STRING
        )
        PARTITIONED BY (year STRING, month STRING, day STRING, hour STRING)
        STORED AS PARQUET
        LOCATION 's3://{trusted_bucket}/logs/'
        TBLPROPERTIES (
            'compressionType'='gzip'
        )
    """)
    
    # Reparar partições
    spark.sql(f"MSCK REPAIR TABLE {database_name}.logs_silver")
    
    print("Tabela logs_silver atualizada no Glue Data Catalog")
else:
    print("Nenhum log válido para processar.")

job.commit()