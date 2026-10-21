import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, sum as spark_sum, count as spark_count, avg, min as spark_min, max as spark_max, round

args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'TRUSTED_BUCKET',
    'CURATED_BUCKET',
    'DATABASE_NAME'
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

trusted_bucket = args['TRUSTED_BUCKET']
curated_bucket = args['CURATED_BUCKET']
database_name = args['DATABASE_NAME']

print(f"Iniciando job TRUSTED -> CURATED")
print(f"Trusted bucket: s3://{trusted_bucket}")
print(f"Curated bucket: s3://{curated_bucket}")
print(f"Database: {database_name}")

# Ler dados da camada TRUSTED - project_data
project_trusted_path = f"s3://{trusted_bucket}/project-data/"
df_project = spark.read.parquet(project_trusted_path)

print(f"Registros lidos do TRUSTED (project-data): {df_project.count()}")

# Enriquecimento e agregações para camada CURATED
# 1. Vendas por estado e mês (para dashboards geográficos)
vendas_estado_mes = df_project.groupBy("estado", "ano", "mes").agg(
    spark_count("*").alias("total_pedidos"),
    spark_sum("valor").alias("receita_total"),
    spark_sum("quantidade").alias("total_itens"),
    round(avg("valor"), 2).alias("ticket_medio"),
    round(avg("quantidade"), 2).alias("itens_medio_por_pedido")
)

# 2. Vendas por categoria e mês (para análise de mix de produtos)
vendas_categoria_mes = df_project.groupBy("categoria", "ano", "mes").agg(
    spark_count("*").alias("total_pedidos"),
    spark_sum("valor").alias("receita_total"),
    spark_sum("quantidade").alias("total_itens"),
    round(avg("valor"), 2).alias("ticket_medio")
)

# 3. Vendas por cliente (para análise de LTV e recorrência)
vendas_cliente = df_project.groupBy("id_cliente", "estado").agg(
    spark_count("*").alias("total_pedidos"),
    spark_sum("valor").alias("valor_total_cliente"),
    spark_sum("quantidade").alias("total_itens_cliente"),
    round(avg("valor"), 2).alias("ticket_medio_cliente"),
    spark_min("data_compra").alias("primeira_compra"),
    spark_max("data_compra").alias("ultima_compra")
)

# 4. Série temporal diária (para análises de sazonalidade)
vendas_diaria = df_project.groupBy("data_compra", "ano", "mes", "dia").agg(
    spark_count("*").alias("pedidos_dia"),
    spark_sum("valor").alias("receita_dia"),
    spark_sum("quantidade").alias("itens_dia"),
    spark_count("id_cliente").alias("clientes_unicos_dia")
)

print(f"Vendas por estado/mês: {vendas_estado_mes.count()}")
print(f"Vendas por categoria/mês: {vendas_categoria_mes.count()}")
print(f"Vendas por cliente: {vendas_cliente.count()}")
print(f"Vendas diárias: {vendas_diaria.count()}")

# Escrever tabelas CURATED
curated_base = f"s3://{curated_bucket}/"

# Tabela 1: vendas_estado_mes
vendas_estado_mes.write \
    .mode("overwrite") \
    .partitionBy("ano", "mes") \
    .parquet(f"{curated_base}vendas_estado_mes/")

# Tabela 2: vendas_categoria_mes
vendas_categoria_mes.write \
    .mode("overwrite") \
    .partitionBy("ano", "mes") \
    .parquet(f"{curated_base}vendas_categoria_mes/")

# Tabela 3: vendas_cliente (não particionado por data, mas por estado)
vendas_cliente.write \
    .mode("overwrite") \
    .partitionBy("estado") \
    .parquet(f"{curated_base}vendas_cliente/")

# Tabela 4: vendas_diaria
vendas_diaria.write \
    .mode("overwrite") \
    .partitionBy("ano", "mes") \
    .parquet(f"{curated_base}vendas_diaria/")

print("Tabelas CURATED gravadas com sucesso")

# Registrar tabelas no Glue Data Catalog
spark.sql(f"CREATE DATABASE IF NOT EXISTS {database_name}")

# vendas_estado_mes
spark.sql(f"""
    CREATE EXTERNAL TABLE IF NOT EXISTS {database_name}.vendas_estado_mes (
        estado STRING,
        total_pedidos BIGINT,
        receita_total DECIMAL(15,2),
        total_itens BIGINT,
        ticket_medio DECIMAL(10,2),
        itens_medio_por_pedido DECIMAL(10,2)
    )
    PARTITIONED BY (ano INT, mes INT)
    STORED AS PARQUET
    LOCATION 's3://{curated_bucket}/vendas_estado_mes/'
""")

# vendas_categoria_mes
spark.sql(f"""
    CREATE EXTERNAL TABLE IF NOT EXISTS {database_name}.vendas_categoria_mes (
        categoria STRING,
        total_pedidos BIGINT,
        receita_total DECIMAL(15,2),
        total_itens BIGINT,
        ticket_medio DECIMAL(10,2)
    )
    PARTITIONED BY (ano INT, mes INT)
    STORED AS PARQUET
    LOCATION 's3://{curated_bucket}/vendas_categoria_mes/'
""")

# vendas_cliente
spark.sql(f"""
    CREATE EXTERNAL TABLE IF NOT EXISTS {database_name}.vendas_cliente (
        id_cliente STRING,
        total_pedidos BIGINT,
        valor_total_cliente DECIMAL(15,2),
        total_itens_cliente BIGINT,
        ticket_medio_cliente DECIMAL(10,2),
        primeira_compra DATE,
        ultima_compra DATE
    )
    PARTITIONED BY (estado STRING)
    STORED AS PARQUET
    LOCATION 's3://{curated_bucket}/vendas_cliente/'
""")

# vendas_diaria
spark.sql(f"""
    CREATE EXTERNAL TABLE IF NOT EXISTS {database_name}.vendas_diaria (
        data_compra DATE,
        pedidos_dia BIGINT,
        receita_dia DECIMAL(15,2),
        itens_dia BIGINT,
        clientes_unicos_dia BIGINT
    )
    PARTITIONED BY (ano INT, mes INT)
    STORED AS PARQUET
    LOCATION 's3://{curated_bucket}/vendas_diaria/'
""")

# Reparar partições
for table in ["vendas_estado_mes", "vendas_categoria_mes", "vendas_cliente", "vendas_diaria"]:
    spark.sql(f"MSCK REPAIR TABLE {database_name}.{table}")
    print(f"Partições reparadas: {table}")

print("Tabelas CURATED registradas no Glue Data Catalog")
job.commit()