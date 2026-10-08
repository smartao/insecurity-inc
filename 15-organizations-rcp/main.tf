# ---------------------------------------------------------------------------
# A Organization é pré-requisito, nunca resource -- mesma decisão (e mesmo
# incidente) do capítulo 14: um "aws_organizations_organization" resource
# chamaria DeleteOrganization no destroy. Ligar RESOURCE_CONTROL_POLICY no
# Root também é pré-requisito manual (CLI/Console -- ver README, Como
# aplicar), pelo mesmo motivo. Aqui ela só fornece o ID usado como
# perímetro em aws:PrincipalOrgID.
# ---------------------------------------------------------------------------

data "aws_organizations_organization" "this" {}

# ---------------------------------------------------------------------------
# RCP com 2 guardrails do lado do recurso -- o complemento da SCP do
# capítulo 14. A SCP limita o que as identidades *da* organização podem
# fazer; nada nela alcança uma identidade de fora (outra conta, ou um
# pedido anônimo) acessando um recurso daqui por meio de uma resource
# policy permissiva demais. A RCP é avaliada junto da resource policy do
# recurso, então vale para qualquer chamador -- inclusive o root de outra
# conta.
#
# Regras de sintaxe de RCP que moldam este documento (ver README):
# - Só Effect = Deny (Allow é exclusivo da RCPFullAWSAccess padrão).
# - Principal só pode ser "*"; quem é barrado se decide no Condition.
# - Action não pode ser "*" sozinho -- cada serviço precisa aparecer
#   explicitamente, e só os serviços da lista de suporte a RCP têm efeito.
# - Sem NotPrincipal nem NotAction.
#
# Escopo de serviços: S3 (capítulo 05), KMS (capítulo 06), Secrets
# Manager (capítulo 08), SQS e o subconjunto de STS que uma identidade
# externa usaria para entrar numa conta. Baseado no exemplo
# identity_perimeter_rcp.json do repositório aws-samples/data-perimeter-
# policy-examples, sem as exceções de terceiros que este lab não tem.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "data_perimeter" {
  # Perímetro de identidade: nega quando o chamador não pertence à
  # organização. "IfExists" faz o pedido *sem* aws:PrincipalOrgID (anônimo,
  # ou de conta standalone) também cair no Deny -- é o que fecha o bucket
  # "acidentalmente público" do Cenário. A exceção para
  # aws:PrincipalIsAWSService deixa passar serviços AWS agindo com o
  # próprio service principal (ex.: CloudTrail entregando log num bucket,
  # capítulo 11), que não têm PrincipalOrgID. Service-linked roles já
  # ficam fora do alcance de RCP por definição da AWS.
  statement {
    sid    = "EnforceOrgIdentities"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:*",
      "kms:*",
      "secretsmanager:*",
      "sqs:*",
      "sts:AssumeRole",
      "sts:DecodeAuthorizationMessage",
      "sts:GetAccessKeyInfo",
      "sts:GetFederationToken",
      "sts:GetServiceBearerToken",
      "sts:GetSessionToken",
      "sts:SetContext",
    ]

    resources = ["*"]

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.this.id]
    }

    condition {
      test     = "BoolIfExists"
      variable = "aws:PrincipalIsAWSService"
      values   = ["false"]
    }
  }

  # TLS obrigatório na organização inteira, não bucket a bucket. O
  # capítulo 05 colocou um DenyInsecureTransport na bucket policy de *um*
  # bucket; esta statement faz o mesmo para todo bucket, chave, secret e
  # fila de qualquer conta onde a RCP estiver anexada -- inclusive os que
  # ainda vão ser criados por alguém que nunca leu o capítulo 05.
  statement {
    sid    = "EnforceSecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:*",
      "kms:*",
      "secretsmanager:*",
      "sqs:*",
      "sts:*",
    ]

    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_organizations_policy" "data_perimeter" {
  name        = "insecurity-inc-data-perimeter"
  description = "Perímetro de dados do lado do recurso: nenhum S3/KMS/Secrets Manager/SQS/STS de conta-membro aceita chamador de fora da organização (nem anônimo), nem requisição sem TLS, independente da resource policy local."
  type        = "RESOURCE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.data_perimeter.json
  tags        = var.tags
}

# Anexada direto na conta-membro, não na OU nem no Root: a AWS recomenda
# explicitamente testar RCP numa conta isolada antes de subir na hierarquia
# (ver README, A Correção). De quebra, o capítulo não precisa importar a
# conta (aws_organizations_account) -- o destroy aqui só desanexa e apaga a
# policy, sem nenhum caminho até RemoveAccountFromOrganization.
resource "aws_organizations_policy_attachment" "data_perimeter" {
  policy_id = aws_organizations_policy.data_perimeter.id
  target_id = var.rcp_target_id
}
