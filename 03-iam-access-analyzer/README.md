# 03 — 🔍 IAM Access Analyzer

![Capa do capítulo 03 — IAM Access Analyzer](../imagens/cover-03.jpg)

**Arco:** Identidade
**Conceito:** Acesso externo não intencional
**Custo:** 🟢

## 🎬 Cenário

A Insecurity Inc. já resolveu o RBAC do plantão de checkout (capítulo 01) e o ABAC entre times (capítulo 02) — mas ironia das ironias, uma empresa cujo produto é "boas práticas de segurança" nunca passou por uma auditoria externa de verdade. Um investidor exige uma antes de fechar a rodada. O fundador contrata uma consultoria de segurança e precisa dar a ela acesso de leitura à conta AWS.

Sem saber ainda o Account ID exato da consultoria (prometeram mandar "por e-mail, mais tarde"), ele entra no console, cria uma IAM Role e resolve não travar o trabalho: em vez de esperar o dado, define o `Principal` da trust policy como `{"AWS": "*"}` — "é só por enquanto, troco assim que eles mandarem o Account ID" — e anexa a policy gerenciada `SecurityAudit`, que dá leitura ampla de configuração de segurança em dezenas de serviços da conta.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAnyoneAssumeForNow",
      "Effect": "Allow",
      "Principal": {"AWS": "*"},
      "Action": "sts:AssumeRole"
    }
  ]
}
```

O "por enquanto" nunca é revisitado. A role fica assim, publicada e esquecida, por meses — e ninguém na Insecurity Inc. tinha, até este capítulo, qualquer mecanismo rodando na conta capaz de notar sozinho que essa trust policy concede acesso a literalmente qualquer principal AWS do planeta.

## 🚨 O Problema

1. **`Principal: {"AWS": "*"}` num trust policy é a pior wildcard possível numa conta AWS.** Sem nenhuma `Condition`, qualquer identidade AWS — de qualquer conta, inclusive uma criada de graça por um atacante minutos atrás — pode chamar `sts:AssumeRole` contra essa role e herdar tudo que `SecurityAudit` concede: leitura de configuração de IAM, S3, EC2, VPC, KMS, CloudTrail e dezenas de outros serviços. É uma técnica de exploração real e catalogada, não um risco teórico (veja [Hacking the Cloud — Misconfigured IAM Role Trust Policy: Wildcard Principal](https://hackingthe.cloud/aws/exploitation/Misconfigured_Resource-Based_Policies/misconfigured_iam_role_trust_policy_wildcard_principal/)).
2. **Confused deputy.** Mesmo que a intenção fosse restringir à consultoria específica, sem um `sts:ExternalId` bastaria alguém descobrir (ou adivinhar — nomes de conta e de role costumam ser previsíveis) o ARN da role para assumi-la. Não há nenhum segredo protegendo o *assume*, só a suposição de que ninguém vai tentar.
3. **Zero detecção contínua.** A conta não tinha nenhum mecanismo rodando para flagar automaticamente esse tipo de exposição. A falha ficaria invisível até uma auditoria manual de cada trust policy, bucket policy e key policy da conta — ou até ser explorada primeiro. O AWS Well-Architected Framework — Security Pillar (SEC03-BP07, *Analyze public and cross-account access*) descreve exatamente esse ponto cego: sem uma ferramenta de análise contínua, acesso público e cross-account concedido por engano tende a passar despercebido.

## ✅ A Correção

Este capítulo resolve dois problemas em paralelo: a trust policy específica do cenário, e a ausência de qualquer detecção contínua de acesso externo na conta.

1. **IAM Access Analyzer** (`aws_accessanalyzer_analyzer`, tipo `ACCOUNT`) — habilita o *external access analyzer* da conta, que passa a varrer continuamente toda policy baseada em recurso (trust policy de IAM Role, bucket policy do S3, key policy do KMS, policy de fila do SQS, de secret do Secrets Manager etc.) e gerar um *finding* sempre que alguma delas conceder acesso a um principal fora da "zone of trust" — aqui, a própria conta. É a ferramenta que o CIS AWS Foundations Benchmark v3.0.0, controle 1.20 (*Ensure that IAM Access Analyzer is enabled*), exige que esteja ligada, e o mecanismo que o SEC03-BP07 recomenda para monitorar continuamente esse tipo de exposição.
2. **Trust policy corrigida** (`insecurity-inc-external-audit-role`):
   - `Principal` escopado ao `arn:aws:iam::<external_account_id>:root` — nunca `"*"`. Por padrão, `var.external_account_id` fica vazio e o Terraform resolve para a própria conta (self-contained, sem exigir uma segunda conta AWS para testar); no cenário real, informa-se o Account ID de fato da consultoria.
   - `Condition StringEquals sts:ExternalId` exigindo um valor combinado com o terceiro fora de banda — a mitigação que a AWS recomenda especificamente contra o confused deputy problem em acesso compartilhado com terceiros (SEC03-BP09, *Share resources securely with a third party*). Diferente de uma senha, o External ID não precisa ser tratado como segredo, mas deve ser único por parceiro e difícil de adivinhar — nunca reaproveitado entre contas diferentes.
   - A managed policy `SecurityAudit` continua anexada — é o "acesso amplo" certo para este caso de uso (leitura de configuração de segurança em dezenas de serviços, zero permissão de escrita), diferente do `AdministratorAccess` usado por engano no capítulo 01.

Com o Access Analyzer ligado, se alguém repetir o erro do Cenário — criar qualquer policy baseada em recurso com um principal externo ou público — a conta passa a denunciar isso sozinha, em vez de depender de alguém lembrar de auditar manualmente.

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar.

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

Por padrão, `var.external_account_id = ""` faz a role apontar para a própria conta (não há Account ID de uma consultoria real neste laboratório). Para simular o cenário real de acesso cross-account, use `-var="external_account_id=<account-id-da-conta-externa>"`.

### ⌨️ Opção 2 — AWS CLI

```bash
# 1. Habilitar o external access analyzer da conta
aws accessanalyzer create-analyzer \
  --analyzer-name insecurity-inc-external-access-analyzer \
  --type ACCOUNT \
  --tags project=insecurity-inc,env=lab,chapter=03

ANALYZER_ARN=$(aws accessanalyzer list-analyzers \
  --query "analyzers[?name=='insecurity-inc-external-access-analyzer'].arn" --output text)

# 2. Criar a trust policy corrigida (Principal escopado + External ID)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
EXTERNAL_ACCOUNT_ID="$ACCOUNT_ID"                  # no cenário real: Account ID da consultoria
EXTERNAL_ID="insecurity-inc-lab-external-id"       # no cenário real: valor único e aleatório por terceiro

cat > /tmp/external-audit-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowExternalAuditorAssumeRoleWithExternalId",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::${EXTERNAL_ACCOUNT_ID}:root"},
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {"sts:ExternalId": "${EXTERNAL_ID}"}
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name insecurity-inc-external-audit-role \
  --assume-role-policy-document file:///tmp/external-audit-trust.json \
  --description "Role de auditoria para a consultoria de segurança externa -- assume restrito à conta configurada + External ID." \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=03

# 3. Anexar a managed policy SecurityAudit (leitura ampla, zero escrita)
aws iam attach-role-policy \
  --role-name insecurity-inc-external-audit-role \
  --policy-arn arn:aws:iam::aws:policy/SecurityAudit
```

### 🖥️ Opção 3 — Console (GUI)

1. **Habilitar o Access Analyzer:** console **IAM** → **Access Analyzer** → **Create analyzer** → **Zone of trust**: "This AWS account" → nome `insecurity-inc-external-access-analyzer` → tags `project=insecurity-inc`, `env=lab`, `chapter=03` → **Create analyzer**.
2. **Criar a role:** **IAM** → **Roles** → **Create role** → **Trusted entity type**: "Custom trust policy" → cole o JSON da Opção 2 (com o Account ID e o External ID reais) → **Next** → em **Add permissions**, marque `SecurityAudit` → **Next** → nome `insecurity-inc-external-audit-role`, descrição "Role de auditoria para a consultoria de segurança externa -- assume restrito à conta configurada + External ID." → tags → **Create role**.

## 🧾 Como testar

O objetivo aqui é ver o Access Analyzer detectar, na prática, o exato erro do Cenário — sem deixar essa exposição de fato na conta. Para isso, reproduza o `Principal: {"AWS": "*"}` numa role **temporária e separada**, criada só por CLI (não pelo Terraform deste capítulo, que só gerencia a versão corrigida), sem nenhuma policy de permissão anexada — o bastante para acionar o *finding*, sem conceder poder nenhum caso alguém de fato a assuma.

> ⚠️ **Erro comum:** se você escrever o Principal como a string solta `"Principal": "*"` (sem o objeto `{"AWS": "*"}` ao redor), o `create-role` falha com `MalformedPolicyDocument: ... invalid principal: "STAR":"*"`. A API do IAM trata esse formato como um tipo especial de principal ("STAR") que `CreateRole` rejeita — o formato realmente aceito, e o que aparece em todo write-up sobre esse tipo de misconfiguration, é `{"AWS": "*"}` (tipo de principal "AWS" com valor `"*"`), usado abaixo.

```bash
# 1. Reproduzir o erro do Cenário numa role descartável, sem nenhuma
#    permissão anexada
cat > /tmp/wildcard-trust.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAnyoneAssumeForNow",
      "Effect": "Allow",
      "Principal": {"AWS": "*"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name insecurity-inc-temp-wildcard-demo \
  --assume-role-policy-document file:///tmp/wildcard-trust.json \
  --description "TEMPORÁRIA -- reproduz o erro do capítulo 03 só para acionar um finding de teste no Access Analyzer. Sem nenhuma policy de permissão anexada."

# 2. Esperar o Access Analyzer avaliar a mudança (pode levar alguns minutos)
#    e listar findings de IAM Role
ANALYZER_ARN=$(aws accessanalyzer list-analyzers \
  --query "analyzers[?name=='insecurity-inc-external-access-analyzer'].arn" --output text)

aws accessanalyzer list-findings \
  --analyzer-arn "$ANALYZER_ARN" \
  --filter '{"resourceType": {"eq": ["AWS::IAM::Role"]}}'
```

Entre os resultados deve aparecer um *finding* apontando para `insecurity-inc-temp-wildcard-demo`, com `"isPublic": true` e o principal `{"AWS": "*"}` — exatamente o padrão que o Cenário descreveu. A role corrigida (`insecurity-inc-external-audit-role`) **não** deve gerar finding algum enquanto `external_account_id` apontar para a própria conta: acesso same-account nunca é "externo" à zone of trust — só principal de outra conta (ou público) é flagado. Se você aplicou com um `external_account_id` de uma conta de fato externa, é esperado que essa role apareça como finding também — nesse caso o Access Analyzer tem uma funcionalidade de *archive rule* para marcar esse tipo de acesso como intencional/aprovado, sem apagar a visibilidade sobre ele (fora do escopo deste laboratório, mas vale conhecer — ver Referências).

Depois do teste, remova a role temporária — o finding correspondente se arquiva automaticamente quando o recurso deixa de existir:

```bash
aws iam delete-role --role-name insecurity-inc-temp-wildcard-demo
```

## 🧹 Como destruir

Destrua pelo mesmo caminho que usou para aplicar (ou combine, já que os nomes de recurso são os mesmos nos três). Se a role temporária da seção "Como testar" ainda existir, remova-a também (comando acima) — ela não é gerenciada por nenhum dos três caminhos abaixo.

### 🏗️ Terraform

```bash
terraform destroy
```

### ⌨️ AWS CLI

```bash
aws iam detach-role-policy \
  --role-name insecurity-inc-external-audit-role \
  --policy-arn arn:aws:iam::aws:policy/SecurityAudit

aws iam delete-role --role-name insecurity-inc-external-audit-role

aws accessanalyzer delete-analyzer \
  --analyzer-name insecurity-inc-external-access-analyzer
```

### 🖥️ Console (GUI)

1. **IAM** → **Roles** → selecione `insecurity-inc-external-audit-role` → **Delete** (confirme a remoção; o console desanexa a `SecurityAudit` automaticamente).
2. **IAM** → **Access Analyzer** → selecione `insecurity-inc-external-access-analyzer` → **Delete**.

## 📚 Referências

- [SEC03-BP07 — Analyze public and cross-account access](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_analyze_cross_account.html) — AWS Well-Architected Framework, Security Pillar; recomenda IAM Access Analyzer como mecanismo de monitoramento contínuo de acesso público/cross-account.
- [SEC03-BP09 — Share resources securely with a third party](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_share_securely_third_party.html) — recomenda External ID único e não reaproveitado como mitigação do confused deputy problem em acesso compartilhado com terceiros.
- [What is Access Analyzer?](https://docs.aws.amazon.com/IAM/latest/UserGuide/what-is-access-analyzer.html) — visão geral oficial do IAM Access Analyzer, tipos de analyzer (`ACCOUNT`/`ORGANIZATION`) e tipos de recurso avaliados.
- [The confused deputy problem](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html) — referência oficial do IAM sobre o problema que o `sts:ExternalId` mitiga.
- [AWS managed policies for job functions — SecurityAudit](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_job-functions.html) — descrição oficial da managed policy usada para a role de auditoria.
- [Hacking the Cloud — Misconfigured IAM Role Trust Policy: Wildcard Principal](https://hackingthe.cloud/aws/exploitation/Misconfigured_Resource-Based_Policies/misconfigured_iam_role_trust_policy_wildcard_principal/) — documentação de segurança ofensiva sobre exploração ativa desse exato padrão de misconfiguração.
- [Security Hub — Controls for AWS Identity and Access Management](https://docs.aws.amazon.com/securityhub/latest/userguide/iam-controls.html) — mapeamento de controles, incluindo CIS AWS Foundations Benchmark v3.0.0, controle 1.20 (*Ensure that IAM Access Analyzer is enabled*).
- [Terraform `aws_accessanalyzer_analyzer`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) — referência do recurso usado neste capítulo.
