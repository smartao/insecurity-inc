data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Tópico SNS que recebe o alerta -- mesmo padrão do capítulo 00 (SNS +
# assinatura de e-mail), mas aqui quem publica não é um CloudWatch Alarm, é
# uma regra do EventBridge.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "config_compliance_alerts" {
  name = "insecurity-inc-config-compliance-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "config_compliance_alerts_email" {
  topic_arn = aws_sns_topic.config_compliance_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# SNS não aceita publish de um serviço da AWS por padrão -- a topic policy
# precisa autorizar events.amazonaws.com explicitamente, restrito (via
# aws:SourceArn) à regra deste capítulo, não a qualquer regra do EventBridge
# que algum dia exista nesta conta.
data "aws_iam_policy_document" "config_compliance_alerts" {
  statement {
    sid    = "AllowEventBridgePublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.config_compliance_alerts.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.config_non_compliant.arn]
    }
  }
}

resource "aws_sns_topic_policy" "config_compliance_alerts" {
  arn    = aws_sns_topic.config_compliance_alerts.arn
  policy = data.aws_iam_policy_document.config_compliance_alerts.json
}

# ---------------------------------------------------------------------------
# Regra do EventBridge -- escuta o barramento default, onde o AWS Config já
# publica nativamente (integração serviço-a-serviço; não depende de trail
# nenhum do capítulo 11). Filtra por "Config Rules Compliance Change", que
# dispara só quando o status de compliance de um recurso, para uma regra,
# MUDA -- não a cada reavaliação periódica que mantém o mesmo resultado --,
# e por complianceType NON_COMPLIANT: voltar a ficar COMPLIANT não gera
# alerta aqui, de propósito (ver README, Dívidas em aberto).
# configRuleName usa "prefix", não a lista fixa das dez regras do capítulo
# 12: qualquer regra insecurity-inc-* criada no futuro já cai neste alerta
# sem precisar tocar neste capítulo.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "config_non_compliant" {
  name        = "insecurity-inc-config-non-compliant"
  description = "Dispara quando uma regra gerenciada do AWS Config (capítulo 12) muda para NON_COMPLIANT."

  event_pattern = jsonencode({
    source      = ["aws.config"]
    detail-type = ["Config Rules Compliance Change"]
    detail = {
      messageType = ["ComplianceChangeNotification"]
      newEvaluationResult = {
        complianceType = ["NON_COMPLIANT"]
      }
      configRuleName = [{ prefix = "insecurity-inc" }]
    }
  })

  tags = var.tags
}

# input_transformer troca o JSON bruto do evento por uma frase legível no
# e-mail -- sem isso, a notificação do SNS é o payload inteiro do evento.
resource "aws_cloudwatch_event_target" "config_non_compliant_sns" {
  rule      = aws_cloudwatch_event_rule.config_non_compliant.name
  target_id = "insecurity-inc-config-non-compliant-sns"
  arn       = aws_sns_topic.config_compliance_alerts.arn

  input_transformer {
    input_paths = {
      rule         = "$.detail.configRuleName"
      resourceType = "$.detail.resourceType"
      resourceId   = "$.detail.resourceId"
      region       = "$.region"
      account      = "$.account"
    }

    input_template = "\"[insecurity-inc] A regra do AWS Config <rule>, na conta <account> (<region>), ficou NON_COMPLIANT para o recurso <resourceId> (<resourceType>). Veja o AWS Config console para detalhes.\""
  }

  depends_on = [aws_sns_topic_policy.config_compliance_alerts]
}
