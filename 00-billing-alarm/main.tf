# As métricas de billing (namespace AWS/Billing) só são publicadas na região
# us-east-1, independente da região usada por var.region ou pelo restante da
# conta. O alarme do CloudWatch e o tópico SNS que ele notifica precisam
# viver nessa região (CloudWatch Alarm não publica em SNS de outra região).
provider "aws" {
  alias  = "billing"
  region = "us-east-1"
}

resource "aws_sns_topic" "billing_alerts" {
  provider = aws.billing
  name     = "insecurity-inc-billing-alerts"
  tags     = var.tags
}

resource "aws_sns_topic_subscription" "billing_alerts_email" {
  provider  = aws.billing
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarme clássico de billing. Pré-requisito manual (não exposto via
# API/Terraform): "Receive Billing Alerts" precisa estar habilitado em
# Billing and Cost Management > Billing preferences. Sem isso a métrica
# EstimatedCharges não é publicada e este alarme nunca sai de INSUFFICIENT_DATA.
resource "aws_cloudwatch_metric_alarm" "billing_estimated_charges" {
  provider            = aws.billing
  alarm_name          = "insecurity-inc-billing-estimated-charges"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600 # 6h — intervalo em que a métrica de billing é publicada
  statistic           = "Maximum"
  threshold           = var.billing_alarm_threshold_usd
  alarm_description   = "Gastos estimados da conta ultrapassaram US$ ${var.billing_alarm_threshold_usd} no mês corrente."
  treat_missing_data  = "notBreaching"

  dimensions = {
    Currency = "USD"
  }

  alarm_actions = [aws_sns_topic.billing_alerts.arn]
  ok_actions    = [aws_sns_topic.billing_alerts.arn]

  tags = var.tags
}

# AWS Budgets: orçamento mensal com notificações escalonadas (gasto real e
# gasto previsto). Diferente do alarme acima, não depende do "Receive Billing
# Alerts" e funciona mesmo sem essa preferência habilitada.
resource "aws_budgets_budget" "monthly_cost" {
  name         = "insecurity-inc-monthly-budget"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
