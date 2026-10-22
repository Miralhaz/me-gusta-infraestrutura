# =============================================================================
# LAMBDA - EXPORT DE ESTOQUE PARA A CAMADA RAW (Bronze)
# =============================================================================
# Esta funcao chama a API REST do backend MeGusta (autenticando via POST /login)
# e grava um CSV por recurso no bucket RAW (megusta-raw-us-east-1), no formato
# de particoes que o Glue espera (ano=/mes=/dia=).
#
# POR QUE NAO CONECTA NO MYSQL DIRETO:
#   O MySQL roda dentro do Docker Swarm, sem porta publicada no host. A Lambda
#   nao alcanca o container na 3306 - entao o caminho e a API REST, que ja
#   expoe os dados com autenticacao JWT.
#
# POR QUE RODA DENTRO DA VPC (vpc_config):
#   O ALB e interno no que diz respeito ao trafego de back-end: apenas o que
#   esta na VPC alcanca o alvo. Alem disso, o backend-sg libera a porta 8080
#   somente para SGs explicitamente autorizados. Colocando a Lambda nas subnets
#   privadas (com o lambda-sg liberado no backend-sg), ela alcanca a API sem
#   expor nada para a internet. A saida para S3/CloudWatch usa o NAT Gateway.
#
# IAM:
#   Segue o mesmo padrao do restante do projeto - NAO cria role (a conta do lab
#   bloqueia iam:CreateRole). Reutiliza a role passada em var.glue_service_role_arn.
# =============================================================================

locals {
  lambda_role_arn = var.glue_service_role_arn

  # URL base da API vista de dentro da VPC.
  # Se api_base_url nao for informada, usa o DNS do ALB na porta 80.
  lambda_api_base_url = coalesce(
    var.api_base_url != "" ? var.api_base_url : null,
    "http://${aws_lb.megusta.dns_name}",
  )
}

# -----------------------------------------------------------------------------
# Security Group da Lambda
# -----------------------------------------------------------------------------
# Saida liberada (S3, CloudWatch, ALB). Sem regra de entrada: a Lambda e
# apenas um cliente, ninguem precisa inicia conexao com ela.
resource "aws_security_group" "lambda" {
  name        = "lambda-sg"
  description = "Security Group da Lambda de export de estoque. Apenas saida."
  vpc_id      = aws_vpc.minha_vpc.id

  egress {
    description = "Libera toda saida (API, S3, CloudWatch)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lambda-sg"
  }
}

# -----------------------------------------------------------------------------
# Empacotamento do codigo
# -----------------------------------------------------------------------------
# Empacota somente o script da Lambda. Nao ha dependencias externas (usa apenas
# stdlib + boto3, que ja vem no runtime), entao o zip e so o .py.
data "archive_file" "export_megusta_estoque" {
  type        = "zip"
  source_file = "${path.module}/../scripts/export_megusta_estoque.py"
  output_path = "${path.module}/build/export_megusta_estoque.zip"
}

# -----------------------------------------------------------------------------
# Funcao Lambda
# -----------------------------------------------------------------------------
resource "aws_lambda_function" "export_megusta_estoque" {
  function_name = "megusta-export-estoque"
  description   = "Exporta insumos/entradas/saidas/fornecedores da API MeGusta para CSV no bucket RAW (S3)."

  role    = local.lambda_role_arn
  handler = "export_megusta_estoque.lambda_handler"
  runtime = "python3.12"

  filename         = data.archive_file.export_megusta_estoque.output_path
  source_code_hash = data.archive_file.export_megusta_estoque.output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  # Dentro da VPC, nas subnets privadas, para alcancar a API e o S3 via NAT.
  vpc_config {
    subnet_ids         = [aws_subnet.privada_web_a.id, aws_subnet.privada_web_b.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      RAW_BUCKET   = data.aws_s3_bucket.raw.bucket
      API_BASE_URL = local.lambda_api_base_url
      API_LOGIN    = var.api_login
      API_PASSWORD = var.api_password
      RAW_PREFIX   = var.raw_prefix
      RECURSOS     = var.lambda_recursos
      # NAO definir AWS_REGION: e uma chave reservada da Lambda. A AWS injeta
      # essa variavel automaticamente com a regiao da funcao. O script apenas
      # a LE (os.environ.get("AWS_REGION", ...)), o que funciona normalmente.
    }
  }

  tags = {
    Name     = "megusta-export-estoque"
    Pipeline = "raw-export"
  }

  depends_on = [aws_security_group.lambda]
}

# -----------------------------------------------------------------------------
# Agendamento (opcional)
# -----------------------------------------------------------------------------
# Dispara a exportacao periodicamente. Por padrao rodando 1x/dia as 03:00 UTC,
# antes do crawler RAW (06:00). Ajuste em var.lambda_schedule_expression.
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  count = var.lambda_schedule_enabled ? 1 : 0

  name                = "megusta-export-estoque-schedule"
  description         = "Dispara a Lambda de export de estoque periodicamente."
  schedule_expression = var.lambda_schedule_expression

  tags = {
    Name = "megusta-export-estoque-schedule"
  }
}

resource "aws_cloudwatch_event_target" "lambda_schedule" {
  count = var.lambda_schedule_enabled ? 1 : 0

  rule      = aws_cloudwatch_event_rule.lambda_schedule[0].name
  target_id = "megusta-export-estoque"
  arn       = aws_lambda_function.export_megusta_estoque.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.lambda_schedule_enabled ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.export_megusta_estoque.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule[0].arn
}

# -----------------------------------------------------------------------------
# Log group dedicado (com retencao controlada)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_export" {
  name              = "/aws/lambda/${aws_lambda_function.export_megusta_estoque.function_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = {
    Name = "megusta-export-estoque-logs"
  }
}
