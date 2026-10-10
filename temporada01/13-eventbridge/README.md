# 13 — ⚡ EventBridge

![Capa do capítulo 13 — EventBridge](../imagens/cover-S01E13.jpg)

**Arco:** Detecção & Auditoria  
**Conceito:** Detecção baseada em eventos  
**Well-Architected:** [SEC04-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_detect_investigate_events_security_alerts.html)  
**Custo:** 🟢  
**Depende de:** capítulo(s) 12

## 🎬 Cenário

O capítulo 12 fechou dez promessas antigas com regras gerenciadas do AWS Config — mas terminou com uma dívida explícita: *"este capítulo só detecta; reagir automaticamente é o assunto do capítulo 13"*. Três semanas depois de o Config entrar no ar, um incidente de madrugada repete quase palavra por palavra o que o fundador fez no capítulo 09: o engenheiro de plantão, sem VPN funcionando, reabre a porta 22 para `0.0.0.0/0` num security group de teste — "só até resolver o acesso" — e segue para o problema de verdade, prometendo fechar a regra depois.

Ele fecha, três dias depois. Nesses três dias, o AWS Config avaliou a mudança corretamente e marcou duas regras como `NON_COMPLIANT` em poucos minutos — exatamente como o capítulo 12 prometeu. Ninguém percebeu. O dashboard do Config existe, é preciso, e não notifica ninguém: alguém precisa abrir o console e olhar. A auditoria que finalmente encontra os três dias de exposição faz a pergunta óbvia: *"o Config sabia disso em tempo real. Por que só descobrimos numa revisão manual?"*

## 🚨 O Problema

1. **AWS Config detecta; não avisa.** `get-compliance-details-by-config-rule` sempre teve a resposta certa — mas é um modelo *pull*: alguém precisa perguntar. Testado nesta conta, antes deste capítulo: nenhum recurso da API do Config, do CloudWatch ou do SNS notifica proativamente uma mudança de compliance. A distância entre "o dado existe" e "alguém sabe" é o problema inteiro deste capítulo.
2. **A resposta clássica do CIS para isso (seção 3/4 "Monitoring", v1.2.0/v1.4.0) já não é mais um controle automatizado do Security Hub.** Os catorze controles `CloudWatch.1`–`CloudWatch.14` — que cobrem exatamente "log metric filter e alarm para mudanças de security group" (`CloudWatch.10`, requisito CIS 3.10/4.10) e "para mudanças de configuração do AWS Config" (`CloudWatch.9`, requisito CIS 3.9/4.9) — aparecem como **"Not supported – manual check"** nas versões v3.0.0 e v5.0.0 do benchmark, as que este repositório usa como referência (ver capítulo 12, Referências). O próprio ecossistema de compliance abandonou o mecanismo antigo sem substituí-lo por um novo controle automatizado — deixou a lacuna aberta.
3. **Mesmo onde esse controle antigo ainda existe (v1.2.0/v1.4.0), ele reage ao evento errado.** Um metric filter sobre `AuthorizeSecurityGroupIngress` no CloudTrail dispara a cada chamada de API — inclusive uma tentativa negada, uma regra criada e revertida em segundos, ou uma porta legítima. Ele prova que a *chamada* aconteceu, não que o *recurso ficou inseguro*. É a mesma distinção que o capítulo 12 já registrou (Problema, pt. 4): "CloudTrail prova evento; não prova estado, nem por quanto tempo."
4. **SEC04-BP03 do Well-Architected é explícito sobre qual serviço fecha essa lacuna.** O passo de implementação 2 da prática diz, literalmente: *"Establish a mechanism for capturing alerts from different sources. Consider services such as Security Hub CSPM, EventBridge, and CloudWatch for this purpose."* — nomeia o EventBridge como o mecanismo de captura, não o CloudWatch Logs Insights que o CIS antigo usava.

## ✅ A Correção

1. **Uma regra do EventBridge no barramento default**, filtrando o evento nativo que o AWS Config já publica (`aws.config` / `Config Rules Compliance Change`) — não um trail do CloudTrail, não um metric filter: integração serviço a serviço, sem custo de captura (ver Nota de custo). O `event_pattern` filtra por três condições ao mesmo tempo:
   - `detail.newEvaluationResult.complianceType = NON_COMPLIANT` — reage à **mudança de estado**, não à chamada de API que a causou (resolve o Problema pt. 3).
   - `detail.configRuleName` com `prefix: "insecurity-inc"` — cobre as dez regras do capítulo 12 **e qualquer regra `insecurity-inc-*` futura**, sem listar nomes fixos.
   - `detail.messageType = ComplianceChangeNotification` — o valor documentado do próprio evento do Config, escopo adicional sem custo.
2. **SNS + e-mail, o mesmo padrão do capítulo 00** — não um destino novo. `var.alert_email` reaproveita a mesma variável (mesmo default). A topic policy autoriza só `events.amazonaws.com`, restrito via `aws:SourceArn` à ARN desta regra específica — o mesmo padrão "mais restrito que a documentação" dos capítulos 06/10/11/12 (a AWS não recomenda restringir por `SourceArn` aqui; só por `SourceAccount`).
3. **`input_transformer` reescreve o payload bruto do evento numa frase em português antes de publicar no SNS** — sem isso, o e-mail recebido é o JSON inteiro do evento, ilegível para quem só precisa saber "o quê, onde, e qual recurso".
4. **Não alerta quando o recurso volta a `COMPLIANT`, de propósito** (ver Dívidas em aberto) — o `complianceType` do event pattern só lista `NON_COMPLIANT`.

## 💵 Nota de custo

Este capítulo, isoladamente, não adiciona custo mensurável:

- **EventBridge:** eventos publicados por um serviço da AWS no barramento default (como o `aws.config` deste capítulo) não são cobrados para casar com regras — cobrança só existe para eventos customizados publicados via `PutEvents`, que este capítulo não usa.
- **SNS:** as primeiras 1.000 notificações por e-mail e o primeiro 1 milhão de publicações por mês são gratuitos — muito acima do volume de um laboratório.
- **CloudWatch (métricas de `Invocations`/`NumberOfMessagesPublished`):** métricas padrão da própria regra/tópico, sem custo adicional.
- O custo real deste arco continua sendo o do **capítulo 12** (item de configuração + avaliação de regra do AWS Config), já documentado lá — este capítulo só consome os eventos que o capítulo 12 já paga para gerar.

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Todos assumem o capítulo 12 já aplicado (o EventBridge não tem o que escutar sem ele).

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

### ⌨️ Opção 2 — AWS CLI

```bash
ALERT_EMAIL="seu-email@exemplo.com"

# 1. Tópico SNS + assinatura por e-mail (precisa ser confirmada clicando no
#    link recebido -- não tem equivalente de API/CLI, é sempre manual).
TOPIC_ARN=$(aws sns create-topic --name insecurity-inc-config-compliance-alerts --query TopicArn --output text)
[ -n "$TOPIC_ARN" ] && [ "$TOPIC_ARN" != None ] || echo "TOPIC_ARN VAZIA -- não continue sem corrigir (confira o login AWS)"
aws sns tag-resource --resource-arn "$TOPIC_ARN" --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=13
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$ALERT_EMAIL"

# 2. Regra do EventBridge -- mesmo event pattern do main.tf.
cat > /tmp/config-non-compliant-pattern.json <<'EOF'
{
  "source": ["aws.config"],
  "detail-type": ["Config Rules Compliance Change"],
  "detail": {
    "messageType": ["ComplianceChangeNotification"],
    "newEvaluationResult": {"complianceType": ["NON_COMPLIANT"]},
    "configRuleName": [{"prefix": "insecurity-inc"}]
  }
}
EOF
RULE_ARN=$(aws events put-rule --name insecurity-inc-config-non-compliant \
  --description "Dispara quando uma regra gerenciada do AWS Config (capítulo 12) muda para NON_COMPLIANT." \
  --event-pattern file:///tmp/config-non-compliant-pattern.json \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=13 \
  --query RuleArn --output text)
[ -n "$RULE_ARN" ] && [ "$RULE_ARN" != None ] || echo "RULE_ARN VAZIA -- não continue sem corrigir"

# 3. Topic policy -- só events.amazonaws.com, só esta regra (aws:SourceArn).
cat > /tmp/sns-topic-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowEventBridgePublish",
    "Effect": "Allow",
    "Principal": {"Service": "events.amazonaws.com"},
    "Action": "SNS:Publish",
    "Resource": "${TOPIC_ARN}",
    "Condition": {"ArnEquals": {"aws:SourceArn": "${RULE_ARN}"}}
  }]
}
EOF
aws sns set-topic-attributes --topic-arn "$TOPIC_ARN" --attribute-name Policy --attribute-value file:///tmp/sns-topic-policy.json

# 4. Target -- SNS com input_transformer (mensagem legível em vez do JSON bruto).
cat > /tmp/event-target.json <<EOF
[{
  "Id": "insecurity-inc-config-non-compliant-sns",
  "Arn": "${TOPIC_ARN}",
  "InputTransformer": {
    "InputPathsMap": {
      "rule": "\$.detail.configRuleName",
      "resourceType": "\$.detail.resourceType",
      "resourceId": "\$.detail.resourceId",
      "region": "\$.region",
      "account": "\$.account"
    },
    "InputTemplate": "\"[insecurity-inc] A regra do AWS Config <rule>, na conta <account> (<region>), ficou NON_COMPLIANT para o recurso <resourceId> (<resourceType>). Veja o AWS Config console para detalhes.\""
  }
}]
EOF
aws events put-targets --rule insecurity-inc-config-non-compliant --targets file:///tmp/event-target.json
```

### 🖥️ Console (GUI)

1. **SNS** → **Topics** → **Create topic** → Standard, nome `insecurity-inc-config-compliance-alerts`.
2. Dentro do tópico → **Create subscription** → Protocol `Email` → endpoint seu e-mail → **Create subscription**. Confirme pelo link recebido (só assim a assinatura sai de "Pending confirmation").
3. **EventBridge** → **Rules** → **Create rule** → nome `insecurity-inc-config-non-compliant`, barramento **default**.
4. **Event pattern** → **Custom pattern (JSON editor)** → cole o mesmo JSON do bloco CLI acima (source `aws.config`, detail-type `Config Rules Compliance Change`, `complianceType: NON_COMPLIANT`, `configRuleName` com prefixo `insecurity-inc`).
5. **Target** → **SNS topic** → selecione o tópico do passo 1 → **Additional settings** → **Configure target input** → **Input Transformer** → mapeie os mesmos cinco campos (`$.detail.configRuleName`, `$.detail.resourceType`, `$.detail.resourceId`, `$.region`, `$.account`) e o mesmo template do passo CLI.
6. O console cria a topic policy automaticamente ao adicionar o SNS como target de uma regra do EventBridge — vale conferir em **SNS** → tópico → **Access policy** que o `Resource`/`Condition` ficou restrito a esta regra, não a "qualquer EventBridge da conta".

## 🧾 Como testar

O objetivo é prova ponta a ponta: uma mudança insegura real (a mesma do Cenário — porta 22 aberta para `0.0.0.0/0`) precisa passar por AWS Config → EventBridge → SNS e chegar como mensagem legível, sem intervenção manual; e a volta a `COMPLIANT` precisa **não** gerar alerta (Correção, ponto 4). Requer os capítulos 12 e 13 aplicados, e deve rodar dentro da pasta deste capítulo.

A confirmação de e-mail do SNS é sempre manual (clicar no link recebido) — não dá para automatizar isso num teste de laboratório. Por isso, a prova abaixo usa uma fila SQS temporária, criada só por CLI (fora do Terraform, como o capítulo 12 fez com o Secrets Manager do capítulo 08), assinada no mesmo tópico: SQS confirma assinatura sozinho, então prova a entrega sem depender de alguém clicar um link.

```bash
SNS_TOPIC_ARN=$(terraform output -raw sns_topic_arn)
EVENT_RULE_NAME=$(terraform output -raw event_rule_name)
for v in SNS_TOPIC_ARN EVENT_RULE_NAME; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (rode dentro da pasta do capítulo e confira o login AWS)"; done

# 1. Fila SQS temporária, assinada no tópico -- só para verificação
#    automatizada; não faz parte do capítulo (ver acima).
QUEUE_URL=$(aws sqs create-queue --queue-name insecurity-inc-13-test-queue --output text --query QueueUrl)
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
aws sqs set-queue-attributes --queue-url "$QUEUE_URL" --attributes "{\"Policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Sid\\\":\\\"AllowSNSPublish\\\",\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"sns.amazonaws.com\\\"},\\\"Action\\\":\\\"sqs:SendMessage\\\",\\\"Resource\\\":\\\"$QUEUE_ARN\\\",\\\"Condition\\\":{\\\"ArnEquals\\\":{\\\"aws:SourceArn\\\":\\\"$SNS_TOPIC_ARN\\\"}}}]}\"}"
aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol sqs --notification-endpoint "$QUEUE_ARN"

# 2. Provoca a mudança insegura -- um security group novo, porta 22 aberta
#    para 0.0.0.0/0, a mesma configuração do Cenário.
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG_ID=$(aws ec2 create-security-group --group-name insecurity-inc-13-test-sg --description "teste temporario cap 13" --vpc-id "$VPC_ID" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0

# 3. Espera a mensagem chegar -- dominado pela latência do próprio AWS
#    Config (descoberta do recurso novo + avaliação), não pelo EventBridge/SNS.
#    Testado nesta conta: a mensagem chegou em ~2 minutos.
for i in $(seq 1 24); do
  MSG=$(aws sqs receive-message --queue-url "$QUEUE_URL" --wait-time-seconds 20 --max-number-of-messages 1 --query 'Messages[0].Body' --output text)
  [ -n "$MSG" ] && [ "$MSG" != None ] && break
done
echo "$MSG"
```

Resultado real, nesta conta — duas mensagens chegaram (o security group de teste viola duas das dez regras do capítulo 12 ao mesmo tempo: `restricted-ssh`, porta 22 exposta, e `vpc-sg-open-only-to-authorized-ports`, porta fora de `authorizedTcpPorts=80,443`), cada uma já na forma legível que o `input_transformer` produz, não o JSON bruto:

```text
[insecurity-inc] A regra do AWS Config insecurity-inc-vpc-sg-open-only-to-authorized-ports, na conta 230650392331 (us-east-1),
ficou NON_COMPLIANT para o recurso sg-05a73a760d32ef59d (AWS::EC2::SecurityGroup). Veja o AWS Config console para detalhes.

[insecurity-inc] A regra do AWS Config insecurity-inc-restricted-ssh, na conta 230650392331 (us-east-1),
ficou NON_COMPLIANT para o recurso sg-05a73a760d32ef59d (AWS::EC2::SecurityGroup). Veja o AWS Config console para detalhes.
```

`vpc-default-security-group-closed` — a terceira regra deste grupo — não avaliou o recurso de teste: ela audita especificamente o security group *default* da VPC, não um security group qualquer criado por um usuário. Comportamento esperado, não uma falha (o recurso de teste não é o default da VPC).

Latência observada, ponta a ponta: o `ResultRecordedTime` da avaliação do AWS Config e o `Timestamp` da mensagem já entregue na fila SQS ficaram **~6 segundos** um do outro — confirma que o EventBridge e o SNS são a parte rápida do caminho. Os ~2 minutos entre criar o security group e a mensagem chegar são quase inteiramente o AWS Config descobrindo o recurso novo e avaliando as regras — a mesma latência de "Configuration changes" que o capítulo 12 já tinha documentado (README daquele capítulo, Dívidas em aberto).

```bash
# 4. Corrige o problema e confirma que voltar a COMPLIANT NÃO gera alerta
#    (Correção, ponto 4) -- purga a fila antes, para não confundir
#    mensagens antigas (ainda não deletadas) com um alerta novo de verdade.
aws sqs purge-queue --queue-url "$QUEUE_URL"
aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0

for i in $(seq 1 18); do
  MSG=$(aws sqs receive-message --queue-url "$QUEUE_URL" --wait-time-seconds 20 --max-number-of-messages 1 --query 'Messages[0].Body' --output text)
  [ -n "$MSG" ] && [ "$MSG" != None ] && { echo "INESPERADO: $MSG"; break; }
done
echo "Confirmado nesta conta: nenhuma mensagem nova depois de voltar a COMPLIANT."

# 5. Métricas nativas confirmam o caminho sem falhas.
aws cloudwatch get-metric-statistics --namespace AWS/Events --metric-name Invocations \
  --dimensions Name=RuleName,Value="$EVENT_RULE_NAME" \
  --start-time "$(date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%S)" --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 60 --statistics Sum --query 'Datapoints[].[Timestamp,Sum]' --output table
# Testado nesta conta: 2 invocações, uma por regra que mudou de estado --
# FailedInvocations, no mesmo intervalo, ficou em zero.

# 6. Limpeza dos recursos de teste (não fazem parte do capítulo).
aws sqs delete-queue --queue-url "$QUEUE_URL"
aws ec2 delete-security-group --group-id "$SG_ID"
```

## 📋 Dívidas em aberto

- **Sem alerta na volta a `COMPLIANT`, de propósito.** O event pattern só lista `NON_COMPLIANT` em `complianceType` — confirmado no Como testar, passo 4. Quem quiser fechar esse loop (ex.: "recurso corrigido" como confirmação positiva) adiciona `"COMPLIANT"` à lista; a decisão aqui foi evitar duplicar o volume de e-mail sem um caso de uso concreto que precise disso.
- **Não implementa SEC04-BP03 por completo.** A prática recomenda **correlacionar e enriquecer** alertas de múltiplas fontes (GuardDuty, Security Hub, Config, logs) antes de notificar — este capítulo tem uma fonte só (AWS Config) e nenhuma correlação, só captura e formata. É o passo de implementação 2 da prática ("establish a mechanism for capturing alerts... consider EventBridge"), não a prática inteira.
- **Não satisfaz literalmente nenhum controle CIS/Security Hub**, apesar de cobrir a mesma necessidade que os antigos `CloudWatch.9`/`CloudWatch.10` cobriam (ver Problema, pt. 2 e 3) — esses controles checam especificamente um log metric filter + alarm sobre eventos do CloudTrail, não uma integração EventBridge↔Config. Não existe hoje um controle automatizado do Security Hub para "reagir a mudanças de compliance do AWS Config via EventBridge".
- **Um único e-mail, sem escalonamento nem agrupamento.** Um incidente que deixa cinco recursos `NON_COMPLIANT` ao mesmo tempo (ex.: uma mudança de IaC malfeita) gera cinco e-mails separados, não um resumo. Um SIEM ou o Amazon Detective (citado nos "Related tools" do SEC04-BP03) resolveriam isso; fora de escopo de um laboratório de conta única.
- **Sem retry nem dead-letter queue no target do EventBridge.** Se o SNS estiver indisponível ou a publicação falhar, o EventBridge tem retry automático por um tempo limitado, mas nenhuma DLQ captura a falha definitiva para investigação posterior. Aceitável na escala deste capítulo; citado porque é a recomendação padrão da AWS para targets de produção.
- **A fila SQS usada no Como testar não é parte do capítulo** — é criada e destruída inteiramente fora do Terraform, só para permitir verificação automatizada sem depender do clique manual de confirmação do e-mail (que não tem equivalente de API). Confira o passo 6 do Como testar antes de considerar o teste concluído.

## 🧹 Como destruir

### 🏗️ Terraform

```bash
terraform destroy
```

### ⌨️ AWS CLI

```bash
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
for v in REGION ACCOUNT_ID; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue"; done

aws events remove-targets --rule insecurity-inc-config-non-compliant --ids insecurity-inc-config-non-compliant-sns
aws events delete-rule --name insecurity-inc-config-non-compliant

TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:insecurity-inc-config-compliance-alerts"
aws sns delete-topic --topic-arn "$TOPIC_ARN"
```

### 🖥️ Console (GUI)

1. **EventBridge** → **Rules** → `insecurity-inc-config-non-compliant` → **Delete**.
2. **SNS** → **Topics** → `insecurity-inc-config-compliance-alerts` → **Delete** (remove o tópico e as assinaturas junto).

Depois do destroy (de qualquer um dos três caminhos), confira que não sobrou nada:

```bash
aws events list-rules --name-prefix insecurity-inc --query 'Rules[].Name' --output text
aws sns list-topics --query "Topics[?contains(TopicArn, 'insecurity-inc')].TopicArn" --output text
# Esperado: as duas saídas vazias
```

## 📚 Referências

- [SEC04-BP03 — Correlate and enrich security alerts](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_detect_investigate_events_security_alerts.html) — AWS Well-Architected Framework, Security Pillar; passo de implementação 2 recomenda literalmente "Consider services such as Security Hub CSPM, EventBridge, and CloudWatch" para capturar alertas — base deste capítulo (ver Dívidas em aberto sobre o que fica de fora).
- [SEC04-BP04 — Initiate remediation for non-compliant resources](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_detect_investigate_events_noncompliant_resources.html) — a continuação natural deste capítulo (remediação automática via SSM Automation, não só alerta), deliberadamente fora de escopo aqui.
- [What Is Amazon EventBridge?](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html) — barramento default, event pattern matching, e por que eventos de serviços da AWS não são cobrados para casar com regras (ver Nota de custo).
- [Monitoring AWS Config with Amazon EventBridge](https://docs.aws.amazon.com/config/latest/developerguide/monitor-config-with-cloudwatchevents.html) — o evento nativo `Config Rules Compliance Change` que este capítulo filtra; base da Correção, ponto 1.
- [Example Compliance Change Notification](https://docs.aws.amazon.com/config/latest/developerguide/example-config-rule-compliance-notification.html) — schema oficial do bloco `detail` (`messageType`, `configRuleName`, `resourceType`, `resourceId`, `newEvaluationResult.complianceType`) — confere campo a campo com o evento real capturado no Como testar.
- [Amazon EventBridge event patterns](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html) — sintaxe de `prefix` usada em `configRuleName`; base da Correção, ponto 1.
- [Amazon EventBridge input transformation](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-transform-target-input.html) — `input_transformer`, `InputPathsMap`/`InputTemplate`; base da Correção, ponto 3.
- [Amazon SNS pricing](https://aws.amazon.com/sns/pricing/) — faixa gratuita de e-mail/publicação citada na Nota de custo.
- [Amazon EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/) — eventos de serviços da AWS no barramento default não são cobrados para casar com regras; base da Nota de custo.
- CIS AWS Foundations Benchmark — `CloudWatch.9`/`CloudWatch.10` (mudanças de configuração do Config / de security group): requisito 3.9/3.10 na v1.2.0, 4.9/4.10 na v1.4.0, **"Not supported – manual check"** nas v3.0.0 e v5.0.0 — [tabela de versões do Security Hub](https://docs.aws.amazon.com/securityhub/latest/userguide/cis-aws-foundations-benchmark.html#cis-version-comparison); base do Problema, pt. 2 e 3.
- Capítulo [12](../12-aws-config/README.md) — origem do evento que este capítulo escuta e das dez regras cobertas pelo `prefix` do event pattern; ver Cenário e Correção, ponto 1.
- Capítulo [00](../00-billing-alarm/README.md) — origem do padrão SNS + e-mail reaproveitado aqui (`var.alert_email`); ver Correção, ponto 2.
- Terraform AWS provider: [`aws_cloudwatch_event_rule`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule), [`aws_cloudwatch_event_target`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target), [`aws_sns_topic`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic), [`aws_sns_topic_policy`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy).
