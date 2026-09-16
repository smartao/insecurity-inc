# 00 — 💰 Billing Alarm & Budgets

![Capa do capítulo 00 — Billing Alarm & Budgets](../imagens/cover-S01E00.jpg)

**Arco:** Fundação  
**Conceito:** Safety net  
**Custo:** 🟢

## 🎬 Cenário

A Insecurity Inc. acabou de abrir a conta AWS e já está ansiosa para começar a colocar a mão na massa nos próximos capítulos deste laboratório. Ninguém configurou nenhum tipo de alerta de gasto: sem free tier, qualquer recurso esquecido rodando, qualquer credencial vazada e usada por terceiros, ou qualquer erro de configuração (ex.: deixar o AWS Config gravando item de configuração sem necessidade) vira uma surpresa desagradável só no fechamento da fatura.

## 🚨 O Problema

Sem visibilidade de custo em tempo (quase) real, a conta opera às cegas: o primeiro sinal de um problema — uso indevido, recurso esquecido, engano de configuração — é o boleto no fim do mês, quando já é tarde para agir. Não existe nenhum "circuit breaker" de observação: nenhum alarme, nenhum orçamento, nenhuma notificação automática.

## ✅ A Correção

Este capítulo implementa duas camadas complementares de alerta de custo, ambas notificando o mesmo e-mail (`alert_email`):

1. **CloudWatch Billing Alarm** — alarme clássico do CloudWatch sobre a métrica `AWS/Billing > EstimatedCharges`, que é publicada apenas na região `us-east-1`, independentemente da região onde os outros recursos da conta rodam. Dispara quando o gasto estimado da conta no mês corrente ultrapassa `billing_alarm_threshold_usd`, e publica no tópico SNS `insecurity-inc-billing-alerts`.
2. **AWS Budgets** — orçamento mensal (`monthly_budget_usd`) com três notificações escalonadas por e-mail: 80% do orçamento realizado, 100% do orçamento realizado e 100% do orçamento previsto (forecast), permitindo agir antes de estourar o valor definido.

**Pré-requisito manual (fora do Terraform):** o CloudWatch Billing Alarm só funciona se a opção **"Receive Billing Alerts"** estiver habilitada em *Billing and Cost Management → Billing preferences*, na conta de management. Essa preferência não é exposta via API/Terraform — sem ela, a métrica `EstimatedCharges` nunca é publicada e o alarme permanece em `INSUFFICIENT_DATA` para sempre. O AWS Budgets **não** depende dessa preferência e funciona independentemente dela.

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar (ex.: aplicar via CLI e depois inspecionar/destruir via Console).

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

O e-mail padrão de notificação já vem definido em `variables.tf` (`alert_email`); para usar outro, passe `-var="alert_email=outro@exemplo.com"`.

Após o `apply`, confirme as **duas** assinaturas de e-mail que chegam na caixa de entrada: uma da assinatura SNS (CloudWatch Alarm) e uma do AWS Budgets. Enquanto não confirmadas, nenhuma notificação é entregue.

> **Importante:** independentemente do caminho escolhido, o passo "Receive Billing Alerts" abaixo não tem equivalente em Terraform nem em CLI — é uma preferência de conta só exposta no Console, e sem ela o CloudWatch Alarm nunca sai de `INSUFFICIENT_DATA`.

### ⌨️ Opção 2 — AWS CLI

```bash
# 0. Habilitar "Receive Billing Alerts" — não existe comando de CLI/API para isso,
# só pelo Console (ver Opção 3, passo 0). Faça esse passo manualmente primeiro.

# 1. Criar o tópico SNS (região us-east-1 — métricas de billing só existem lá)
aws sns create-topic \
  --name insecurity-inc-billing-alerts \
  --region us-east-1 \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=00
# guarde o TopicArn retornado, ex.: arn:aws:sns:us-east-1:123456789012:insecurity-inc-billing-alerts
TOPIC_ARN=<TopicArn retornado acima>

# 2. Assinar o e-mail no tópico
aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol email \
  --notification-endpoint seu-email@exemplo.com \
  --region us-east-1
# confirme a assinatura no e-mail recebido antes de seguir

# 3. Criar o CloudWatch Alarm sobre AWS/Billing > EstimatedCharges
aws cloudwatch put-metric-alarm \
  --alarm-name insecurity-inc-billing-estimated-charges \
  --alarm-description "Gastos estimados da conta ultrapassaram US\$ 10 no mês corrente." \
  --namespace AWS/Billing \
  --metric-name EstimatedCharges \
  --dimensions Name=Currency,Value=USD \
  --statistic Maximum \
  --period 21600 \
  --evaluation-periods 1 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" \
  --ok-actions "$TOPIC_ARN" \
  --region us-east-1 \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=00

# 4. Criar o AWS Budget mensal com as três notificações escalonadas
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > /tmp/budget.json <<'EOF'
{
  "BudgetName": "insecurity-inc-monthly-budget",
  "BudgetLimit": { "Amount": "10", "Unit": "USD" },
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY"
}
EOF

cat > /tmp/notifications.json <<'EOF'
[
  {
    "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 80, "ThresholdType": "PERCENTAGE" },
    "Subscribers": [{ "SubscriptionType": "EMAIL", "Address": "seu-email@exemplo.com" }]
  },
  {
    "Notification": { "NotificationType": "ACTUAL", "ComparisonOperator": "GREATER_THAN", "Threshold": 100, "ThresholdType": "PERCENTAGE" },
    "Subscribers": [{ "SubscriptionType": "EMAIL", "Address": "seu-email@exemplo.com" }]
  },
  {
    "Notification": { "NotificationType": "FORECASTED", "ComparisonOperator": "GREATER_THAN", "Threshold": 100, "ThresholdType": "PERCENTAGE" },
    "Subscribers": [{ "SubscriptionType": "EMAIL", "Address": "seu-email@exemplo.com" }]
  }
]
EOF

aws budgets create-budget \
  --account-id "$ACCOUNT_ID" \
  --budget file:///tmp/budget.json \
  --notifications-with-subscribers file:///tmp/notifications.json \
  --region us-east-1
```

### 🖥️ Opção 3 — Console (GUI)

0. **Habilitar alertas de billing (pré-requisito):** faça login com um usuário com permissão em Billing → **Billing and Cost Management** → **Billing preferences** → marque **"Receive Billing Alerts"** → **Save preferences**.
1. **Criar o tópico SNS:** console **SNS**, confirme a região **us-east-1** (canto superior direito) → **Topics** → **Create topic** → tipo **Standard**, nome `insecurity-inc-billing-alerts` → em *Tags*, adicione `project=insecurity-inc`, `env=lab`, `chapter=00` → **Create topic**.
2. **Assinar o e-mail:** dentro do tópico criado → **Create subscription** → protocolo **Email** → endpoint = seu e-mail → **Create subscription**. Confirme a assinatura no e-mail recebido.
3. **Criar o CloudWatch Alarm:** console **CloudWatch** (região us-east-1) → **Alarms** → **All alarms** → **Create alarm** → **Select metric** → **Billing** → **Total Estimated Charge** → marque a métrica com `Currency = USD` → **Select metric**.
   - *Statistic*: Maximum · *Period*: 6 hours.
   - *Condition*: Static → Greater → `10` (ou o valor de `billing_alarm_threshold_usd`).
   - *Configure actions*: em **Alarm state trigger** e também em **OK state trigger**, selecione **Select an existing SNS topic** → `insecurity-inc-billing-alerts`.
   - Nome do alarme: `insecurity-inc-billing-estimated-charges` → **Create alarm**.
4. **Criar o AWS Budget:** **Billing and Cost Management** → **Budgets** → **Create budget** → **Customize (advanced)** → tipo **Cost budget**.
   - Nome: `insecurity-inc-monthly-budget` · Período: **Monthly** · *Budgeted amount*: `10` USD.
   - **Add an alert threshold**: 80% do valor **Actual** → e-mail.
   - Adicione mais dois alertas: 100% **Actual** e 100% **Forecasted**, ambos notificando o mesmo e-mail.
   - **Create budget**.

## 🧹 Como destruir

Destrua pelo mesmo caminho que usou para aplicar (ou combine, já que os nomes de recurso são os mesmos nos três).

### 🏗️ Terraform

```bash
terraform destroy
```

### ⌨️ AWS CLI

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws budgets delete-budget \
  --account-id "$ACCOUNT_ID" \
  --budget-name insecurity-inc-monthly-budget \
  --region us-east-1

aws cloudwatch delete-alarms \
  --alarm-names insecurity-inc-billing-estimated-charges \
  --region us-east-1

# Se $TOPIC_ARN não estiver mais no shell (sessão nova), recupere-o:
TOPIC_ARN=$(aws sns list-topics --region us-east-1 \
  --query "Topics[?ends_with(TopicArn, ':insecurity-inc-billing-alerts')].TopicArn" \
  --output text)

aws sns delete-topic \
  --topic-arn "$TOPIC_ARN" \
  --region us-east-1
# delete-topic já remove as assinaturas associadas
```

### 🖥️ Console (GUI)

1. **Budgets** → selecione `insecurity-inc-monthly-budget` → **Delete**.
2. **CloudWatch** → **Alarms** → selecione `insecurity-inc-billing-estimated-charges` → **Delete** → confirme.
3. **SNS** → **Topics** → selecione `insecurity-inc-billing-alerts` → **Delete** → confirme (remove a assinatura junto).
4. "Receive Billing Alerts" pode ficar habilitado — não gera custo e não precisa ser revertido.

## 📚 Referências

- [Setting an Amazon CloudWatch alarm on estimated charges](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html) — pré-requisito de habilitar "Receive Billing Alerts" e detalhes da métrica `EstimatedCharges`.
- [Managing your costs with AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- AWS Well-Architected Framework — Cost Optimization Pillar (COST02: How do you govern usage?)
