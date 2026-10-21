# ==========================================
# SNS TOPIC PARA ALERTAS
# ==========================================
resource "aws_sns_topic" "alerts" {
  name = "megusta-alerts"

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# ==========================================
# CLOUDWATCH LOG GROUPS
# ==========================================
resource "aws_cloudwatch_log_group" "fluentbit" {
  name              = "/aws/ec2/megusta/fluent-bit"
  retention_in_days = 30

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/aws/ec2/megusta/nginx"
  retention_in_days = 30

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

resource "aws_cloudwatch_log_group" "docker" {
  name              = "/aws/ec2/megusta/docker"
  retention_in_days = 30

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

resource "aws_cloudwatch_log_group" "system" {
  name              = "/aws/ec2/megusta/system"
  retention_in_days = 30

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

# ==========================================
# CLOUDWATCH DASHBOARD
# ==========================================
resource "aws_cloudwatch_dashboard" "megusta" {
  dashboard_name = "megusta-infrastructure"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 CPU Utilization - All Instances"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.bastion_host_a.id, { label : "Bastion A" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.bastion_host_b.id, { label : "Bastion B" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web_server_a.id, { label : "Web A" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.web_server_b.id, { label : "Web B" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.backend_a.id, { label : "Backend A" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.backend_b.id, { label : "Backend B" }],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.database_a.id, { label : "Database A" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "EC2 Memory Utilization - All Instances"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.bastion_host_a.id, { label : "Bastion A" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.bastion_host_b.id, { label : "Bastion B" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.web_server_a.id, { label : "Web A" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.web_server_b.id, { label : "Web B" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.backend_a.id, { label : "Backend A" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.backend_b.id, { label : "Backend B" }],
            ["CWAgent", "mem_used_percent", "InstanceId", aws_instance.database_a.id, { label : "Database A" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "EC2 Disk Usage - All Instances"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.bastion_host_a.id, { label : "Bastion A" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.bastion_host_b.id, { label : "Bastion B" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.web_server_a.id, { label : "Web A" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.web_server_b.id, { label : "Web B" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.backend_a.id, { label : "Backend A" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.backend_b.id, { label : "Backend B" }],
            ["CWAgent", "disk_used_percent", "InstanceId", aws_instance.database_a.id, { label : "Database A" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "EC2 Network In/Out - All Instances"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.bastion_host_a.id, { label : "Bastion A In" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.bastion_host_a.id, { label : "Bastion A Out" }],
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.web_server_a.id, { label : "Web A In" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.web_server_a.id, { label : "Web A Out" }],
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.backend_a.id, { label : "Backend A In" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.backend_a.id, { label : "Backend A Out" }],
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.database_a.id, { label : "DB A In" }],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.database_a.id, { label : "DB A Out" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "ALB Metrics"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.megusta.arn_suffix, { label : "Request Count" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.megusta.arn_suffix, { label : "Target Response Time (ms)" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", aws_lb.megusta.arn_suffix, { label : "2xx Responses" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.megusta.arn_suffix, { label : "4xx Responses" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.megusta.arn_suffix, { label : "5xx Responses" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.megusta.arn_suffix, { label : "Healthy Hosts" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", aws_lb.megusta.arn_suffix, { label : "Unhealthy Hosts" }]
          ]
          period = 60
          stat   = "Sum"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title   = "EFS Metrics"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EFS", "TotalIOBytes", "FileSystemId", aws_efs_file_system.megusta.id, { label : "Total I/O Bytes" }],
            ["AWS/EFS", "ReadIOBytes", "FileSystemId", aws_efs_file_system.megusta.id, { label : "Read I/O Bytes" }],
            ["AWS/EFS", "WriteIOBytes", "FileSystemId", aws_efs_file_system.megusta.id, { label : "Write I/O Bytes" }],
            ["AWS/EFS", "BurstCreditBalance", "FileSystemId", aws_efs_file_system.megusta.id, { label : "Burst Credit Balance" }],
            ["AWS/EFS", "ClientConnections", "FileSystemId", aws_efs_file_system.megusta.id, { label : "Client Connections" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title   = "S3 Bucket Metrics"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", data.aws_s3_bucket.raw.bucket, "StorageType", "StandardStorage", { label : "Raw Bucket Size" }],
            ["AWS/S3", "NumberOfObjects", "BucketName", data.aws_s3_bucket.raw.bucket, "StorageType", "AllStorageTypes", { label : "Raw Objects" }],
            ["AWS/S3", "BucketSizeBytes", "BucketName", data.aws_s3_bucket.trusted.bucket, "StorageType", "StandardStorage", { label : "Trusted Bucket Size" }],
            ["AWS/S3", "NumberOfObjects", "BucketName", data.aws_s3_bucket.trusted.bucket, "StorageType", "AllStorageTypes", { label : "Trusted Objects" }],
            ["AWS/S3", "BucketSizeBytes", "BucketName", data.aws_s3_bucket.curated.bucket, "StorageType", "StandardStorage", { label : "Curated Bucket Size" }],
            ["AWS/S3", "NumberOfObjects", "BucketName", data.aws_s3_bucket.curated.bucket, "StorageType", "AllStorageTypes", { label : "Curated Objects" }]
          ]
          period = 86400
          stat   = "Average"
          region = var.aws_region
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title   = "Glue Job Metrics"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", aws_glue_job.raw_to_trusted.name, { label : "Raw->Trusted Tasks" }],
            ["AWS/Glue", "glue.driver.aggregate.numFailedTasks", "JobName", aws_glue_job.raw_to_trusted.name, { label : "Raw->Trusted Failed" }],
            ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", aws_glue_job.trusted_to_curated.name, { label : "Trusted->Curated Tasks" }],
            ["AWS/Glue", "glue.driver.aggregate.numFailedTasks", "JobName", aws_glue_job.trusted_to_curated.name, { label : "Trusted->Curated Failed" }],
            ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", aws_glue_job.logs_bronze_to_silver.name, { label : "Logs Bronze->Silver Tasks" }],
            ["AWS/Glue", "glue.driver.aggregate.numFailedTasks", "JobName", aws_glue_job.logs_bronze_to_silver.name, { label : "Logs Bronze->Silver Failed" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
        }
      }
    ]
  })
}

# ==========================================
# CLOUDWATCH ALARMS - EC2
# ==========================================
resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  count = length([
    aws_instance.bastion_host_a,
    aws_instance.bastion_host_b,
    aws_instance.web_server_a,
    aws_instance.web_server_b,
    aws_instance.backend_a,
    aws_instance.backend_b,
    aws_instance.database_a
  ])

  alarm_name          = "megusta-ec2-cpu-high-${element([aws_instance.bastion_host_a, aws_instance.bastion_host_b, aws_instance.web_server_a, aws_instance.web_server_b, aws_instance.backend_a, aws_instance.backend_b, aws_instance.database_a], count.index).id}"
  alarm_description   = "CPU utilization above 80% for 5 minutes"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = element([
      aws_instance.bastion_host_a,
      aws_instance.bastion_host_b,
      aws_instance.web_server_a,
      aws_instance.web_server_b,
      aws_instance.backend_a,
      aws_instance.backend_b,
      aws_instance.database_a
    ], count.index).id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

resource "aws_cloudwatch_metric_alarm" "ec2_status_check_failed" {
  count = length([
    aws_instance.bastion_host_a,
    aws_instance.bastion_host_b,
    aws_instance.web_server_a,
    aws_instance.web_server_b,
    aws_instance.backend_a,
    aws_instance.backend_b,
    aws_instance.database_a
  ])

  alarm_name          = "megusta-ec2-status-check-failed-${element([aws_instance.bastion_host_a, aws_instance.bastion_host_b, aws_instance.web_server_a, aws_instance.web_server_b, aws_instance.backend_a, aws_instance.backend_b, aws_instance.database_a], count.index).id}"
  alarm_description   = "Instance status check failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = element([
      aws_instance.bastion_host_a,
      aws_instance.bastion_host_b,
      aws_instance.web_server_a,
      aws_instance.web_server_b,
      aws_instance.backend_a,
      aws_instance.backend_b,
      aws_instance.database_a
    ], count.index).id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

# ==========================================
# CLOUDWATCH ALARMS - ALB
# ==========================================
resource "aws_cloudwatch_metric_alarm" "alb_target_response_time_high" {
  alarm_name          = "megusta-alb-target-response-time-high"
  alarm_description   = "ALB target response time above 5 seconds"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 5
  treat_missing_data  = "missing"

  dimensions = {
    LoadBalancer = aws_lb.megusta.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "megusta-alb-5xx-errors"
  alarm_description   = "ALB 5xx errors detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "missing"

  dimensions = {
    LoadBalancer = aws_lb.megusta.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "megusta-alb-unhealthy-hosts"
  alarm_description   = "ALB has unhealthy targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "missing"

  dimensions = {
    LoadBalancer = aws_lb.megusta.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

# ==========================================
# CLOUDWATCH ALARMS - EFS
# ==========================================
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits_low" {
  alarm_name          = "megusta-efs-burst-credits-low"
  alarm_description   = "EFS burst credits below 10%"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 1000000000
  treat_missing_data  = "missing"

  dimensions = {
    FileSystemId = aws_efs_file_system.megusta.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

# ==========================================
# CLOUDWATCH ALARMS - GLUE JOBS
# ==========================================
resource "aws_cloudwatch_metric_alarm" "glue_job_failed" {
  count = 3

  alarm_name          = "megusta-glue-job-failed-${element([aws_glue_job.raw_to_trusted, aws_glue_job.trusted_to_curated, aws_glue_job.logs_bronze_to_silver], count.index).name}"
  alarm_description   = "Glue job has failed tasks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "AWS/Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "missing"

  dimensions = {
    JobName = element([
      aws_glue_job.raw_to_trusted,
      aws_glue_job.trusted_to_curated,
      aws_glue_job.logs_bronze_to_silver
    ], count.index).name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

# ==========================================
# CLOUDWATCH ALARMS - S3
# ==========================================
resource "aws_cloudwatch_metric_alarm" "s3_raw_bucket_size_large" {
  alarm_name          = "megusta-s3-raw-bucket-size-large"
  alarm_description   = "Raw bucket size above 100GB"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400
  statistic           = "Average"
  threshold           = 107374182400
  treat_missing_data  = "missing"

  dimensions = {
    BucketName  = data.aws_s3_bucket.raw.bucket
    StorageType = "StandardStorage"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

# ==========================================
# CLOUDWATCH ALARMS - RDS (para compatibilidade futura)
# ==========================================
# Nota: Como removemos o RDS gerenciado, estes alarmes são para quando
# a instância EC2 de banco de dados tiver o CloudWatch Agent instalado
resource "aws_cloudwatch_metric_alarm" "db_disk_space_low" {
  alarm_name          = "megusta-db-disk-space-low"
  alarm_description   = "Database instance disk space below 20%"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "disk_free_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  treat_missing_data  = "missing"

  dimensions = {
    InstanceId = aws_instance.database_a.id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = {
    Environment = "prod"
    Project     = "megusta"
  }
}

