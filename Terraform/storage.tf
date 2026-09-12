resource "aws_s3_bucket" "raw" {
  bucket = "megusta-raw-us-east-1"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = {
    Name        = "megusta-raw"
    Environment = "prod"
    Layer       = "raw"
  }
}

resource "aws_s3_bucket" "trusted" {
  bucket = "megusta-trusted-us-east-1"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = {
    Name        = "megusta-trusted"
    Environment = "prod"
    Layer       = "trusted"
  }
}

resource "aws_s3_bucket" "curated" {
  bucket = "megusta-curated-us-east-1"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = {
    Name        = "megusta-curated"
    Environment = "prod"
    Layer       = "curated"
  }
}

resource "aws_s3_bucket" "relatorios" {
  bucket = "megusta-relatorios-us-east-1"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning {
    enabled = true
  }

  tags = {
    Name        = "megusta-relatorios"
    Environment = "prod"
    Layer       = "relatorios"
  }
}