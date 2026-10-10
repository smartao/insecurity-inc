# 07 — ⚙️ Parameter Store

![Capa do capítulo 07 — Parameter Store](../imagens/cover-S01E07.jpg)

**Arco:** Dados  
**Conceito:** Config segura  
**Well-Architected:** [SEC08-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_encrypt.html)  
**Custo:** 🟢  

## 🎬 Cenário

Depois do capítulo 06 corrigir a cifra dos recibos no S3, o time do checkout ataca uma dívida mais antiga e mais incômoda: a senha do banco de dados e a API key do gateway de pagamento ainda são copiadas manualmente para cada instância EC2 durante o deploy, soltas numa variável de ambiente. Sem central de verdade, sem histórico de quem mudou o quê, visível em texto claro para qualquer um com acesso à instância. O desenvolvedor responsável decide corrigir isso adotando o AWS Systems Manager Parameter Store — um lugar único, versionado, para guardar config.

Ele cria os primeiros parâmetros pelo Console. Na tela de criação, o tipo **String** vem pré-selecionado; **SecureString** existe uma opção abaixo, mas pede uma chave KMS extra pra escolher, e ele está com pressa — "não tá exposto na internet feito um bucket, só quem já tem acesso à conta AWS chega nisso". Termina com o equivalente a:

```bash
aws ssm put-parameter --name db_password --value 'S3nhaReal!23' --type String
aws ssm put-parameter --name payment_gateway_api_key --value 'sk_live_xxx' --type String
aws ssm put-parameter --name feature_checkout_v2_enabled --value 'false' --type String
```

Sem hierarquia nenhuma de path — três nomes soltos, "porque ainda não tem múltiplos ambientes, não precisa complicar". Quando chega a vez de escrever a IAM policy que dá à aplicação do checkout permissão para ler esses parâmetros, essa escolha cobra o preço: sem um prefixo comum para escopar o `Resource`, o caminho mais rápido — e o que o desenvolvedor segue — é:

```json
{
  "Effect": "Allow",
  "Action": ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"],
  "Resource": "arn:aws:ssm:us-east-1:123456789012:parameter/*"
}
```

que não concede acesso só aos três parâmetros do checkout — concede acesso a **qualquer** parâmetro que qualquer time da conta venha a criar dali em diante, inclusive segredos de times que ainda nem existem.

## 🚨 O Problema

1. **`String` em vez de `SecureString` para dado sensível.** O valor volta em texto claro na resposta de qualquer chamada bem-sucedida de `ssm:GetParameter` — sem nenhuma barreira além de já ter essa permissão de IAM. `SecureString` pelo menos obriga o parâmetro `WithDecryption` explícito para retornar o texto claro (sem ele, a resposta vem cifrada e ilegível) e cifra o valor em repouso — melhor que nada, mesmo que (como a seção Correção detalha) não seja o segundo portão independente que talvez pareça ser.
2. **Nomenclatura "flat" força `Resource: "*"` na IAM policy.** Sem um prefixo hierárquico comum entre os parâmetros do checkout, não existe um jeito limpo de escopar a permissão de leitura só a eles — a opção mais rápida vira "todo o Parameter Store da conta". Mesma classe de erro do capítulo 01 (excesso de privilégio), desta vez nascida de uma decisão de nomenclatura, não de um copy-paste de policy gerenciada. O raio de explosão não é mais "os dois segredos do checkout" — é qualquer parâmetro que qualquer time da conta guardar dali em diante.
3. **Nenhum controle detectivo automatizado cobre esse erro.** Ao contrário do S3 (Block Public Access, capítulo 05) e do KMS (Access Analyzer + Security Hub KMS.5, capítulo 06), o Parameter Store não tem nenhum equivalente. A [lista oficial de regras gerenciadas do AWS Config](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html) só cobre SSM Automation e SSM Documents (`ssm-automation-block-public-sharing`, `ssm-automation-logging-enabled`, `ssm-document-not-public`, `ssm-document-tagged`) — nenhuma regra sobre parâmetro em texto claro ou `Resource: "*"` em IAM policy de Parameter Store, e o AWS Security Hub também não tem controle equivalente para este serviço. Esse erro passaria batido indefinidamente, sem gerar *finding* nenhum.

## ✅ A Correção

1. **`SecureString` para os dois valores sensíveis** (`db_password`, `payment_gateway_api_key`), cifrados com a chave gerenciada pela AWS `alias/aws/ssm` — sem custo adicional de CMK, mantendo este capítulo 🟢 (ver ponto 5 abaixo para o porquê de não reaproveitar a CMK do capítulo 06 aqui). A feature flag continua `String` — contraste deliberado: nem tudo é sensível, e cifrar tudo indiscriminadamente não é o oposto do Problema, é só outro jeito de não pensar sobre o dado que está sendo guardado.
2. **Hierarquia de path** (`/insecurity-inc/checkout/prod/...`, `var.parameter_path_prefix`) — resolve o ponto 2 do Problema: dá um prefixo comum para escopar o `Resource` da IAM policy a exatamente os parâmetros do checkout, não à árvore inteira da conta.
3. **Role dedicada** (`insecurity-inc-checkout-backend`) **com policy só de leitura**, escopada ao prefixo acima. O `Resource` da policy tem **duas entradas**, não uma — `.../prod` e `.../prod/*` — porque `ssm:GetParametersByPath` avalia o path exato, sem `/*` no final, enquanto `ssm:GetParameter`/`GetParameters` avaliam o nome completo do parâmetro, que exige o `/*`; um único padrão (`.../prod*`, sem a barra) até cobriria as duas actions, mas colidiria por acidente com um path irmão que começasse com o mesmo prefixo (ex.: `/insecurity-inc/checkout/prod-staging`). As duas entradas explícitas evitam essa colisão — pegadinha confirmada testando contra a conta real deste laboratório (ver Como testar).
4. **`ssm:DescribeParameters` com `Resource: "*"`** — a action não suporta permissão a nível de recurso (mesma limitação documentada de `ec2:DescribeInstances` no capítulo 01), e não revela valor nenhum, só metadados (nome, tipo, data de edição). Concessão consciente e documentada, não um descuido.
5. **Nenhuma statement de `kms:Decrypt` na policy — de propósito.** A [documentação oficial do Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/secure-string-parameter-kms-encryption.html) é explícita: *"you cannot establish access control policies for the default aws/ssm KMS key"* — ou seja, não existe uma key policy sua para atuar como segundo portão, como na CMK do capítulo 06. Testado contra a conta real deste capítulo: a própria role `insecurity-inc-checkout-backend`, que não tem **nenhuma** permissão de KMS na policy, decifra o `db_password` normalmente (passo 4 de Como testar). Com a chave padrão, um `Allow` de `kms:Decrypt` não é necessário: o que autoriza a leitura do valor decifrado é o `ssm:GetParameter`. É por isso que o escopo por prefixo do ponto 3 carrega o peso deste capítulo. Um segundo portão independente, nos mesmos moldes do capítulo 06, exigiria uma CMK própria (`key_id` customizado no lugar de `alias/aws/ssm`) — perfeitamente possível, mas com o mesmo custo recorrente (~US$1/mês) do capítulo 06, fora do escopo 🟢 deste.

Fica uma dívida em aberto, citada de propósito: nem `SecureString` resolve rotação — um valor cifrado hoje continua o mesmo valor daqui a um ano, a menos que alguém troque manualmente. É exatamente essa lacuna que o capítulo 08 (Secrets Manager) resolve com rotação nativa.

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar.

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

### ⌨️ Opção 2 — AWS CLI

```bash
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
PREFIX="/insecurity-inc/checkout/prod"

# 1. Segredos de laboratório gerados na hora -- nunca hardcode um valor real
#    num comando de shell (fica no histórico do terminal).
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9!#%*()_+=-' | head -c24)
API_KEY=$(openssl rand -base64 40 | tr -dc 'A-Za-z0-9' | head -c40)

# 2. Parâmetros -- SecureString para os dois sensíveis (sem --key-id: usa a
#    chave gerenciada pela AWS alias/aws/ssm por padrão), String para a flag.
aws ssm put-parameter --name "${PREFIX}/db_password" \
  --description "Senha do banco de dados do checkout (dado de laboratório)." \
  --type SecureString --value "$DB_PASSWORD" \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=07

aws ssm put-parameter --name "${PREFIX}/payment_gateway_api_key" \
  --description "API key do gateway de pagamento usado pelo checkout (dado de laboratório)." \
  --type SecureString --value "$API_KEY" \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=07

aws ssm put-parameter --name "${PREFIX}/feature_checkout_v2_enabled" \
  --description "Feature flag do checkout v2 -- não sensível." \
  --type String --value "false" \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=07

# 3. Role da aplicação de checkout -- trust simplificado para a própria
#    identidade que roda estes comandos, só para manter o laboratório
#    self-contained e testável via "sts assume-role" sem precisar de uma
#    instância EC2 (no cenário real, o trust seria para ec2.amazonaws.com).
cat > /tmp/checkout-backend-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "${CALLER_ARN}"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name insecurity-inc-checkout-backend \
  --assume-role-policy-document file:///tmp/checkout-backend-trust.json \
  --description "Role da aplicação de checkout -- escopada só à leitura de config sob ${PREFIX}." \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=07

# 4. Policy de leitura escopada ao prefixo do checkout -- duas entradas no
#    Resource da primeira statement (ver README, seção Correção, ponto 3).
cat > /tmp/checkout-backend-parameter-read.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadCheckoutProdParameters",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"],
      "Resource": [
        "arn:aws:ssm:${REGION}:${ACCOUNT_ID}:parameter${PREFIX}",
        "arn:aws:ssm:${REGION}:${ACCOUNT_ID}:parameter${PREFIX}/*"
      ]
    },
    {
      "Sid": "DescribeParametersRequiresWildcardResource",
      "Effect": "Allow",
      "Action": "ssm:DescribeParameters",
      "Resource": "*"
    }
  ]
}
EOF

POLICY_ARN=$(aws iam create-policy \
  --policy-name insecurity-inc-checkout-backend-parameter-read \
  --description "Leitura (não escrita) dos parâmetros de config do checkout sob ${PREFIX}." \
  --policy-document file:///tmp/checkout-backend-parameter-read.json \
  --query Policy.Arn --output text)

aws iam attach-role-policy \
  --role-name insecurity-inc-checkout-backend \
  --policy-arn "$POLICY_ARN"

rm -f /tmp/checkout-backend-trust.json /tmp/checkout-backend-parameter-read.json
```

### 🖥️ Opção 3 — Console (GUI)

1. **Criar os parâmetros:** console **Systems Manager** → **Parameter Store** → **Create parameter**.
   - Nome `/insecurity-inc/checkout/prod/db_password` → Tier **Standard** → Type **SecureString** → **KMS key source: My current account** → **alias/aws/ssm** (a chave padrão) → Value: uma senha qualquer de laboratório → tags `project=insecurity-inc`, `env=lab`, `chapter=07` → **Create parameter**.
   - Repita para `/insecurity-inc/checkout/prod/payment_gateway_api_key` (também **SecureString**).
   - Repita para `/insecurity-inc/checkout/prod/feature_checkout_v2_enabled`, mas com Type **String** e Value `false`.
2. **Criar a role:** console **IAM** → **Roles** → **Create role** → **Custom trust policy** → cole a trust policy do JSON da Opção 2 (com o ARN da sua própria identidade) → **Next** → não anexe nenhuma policy gerenciada ainda → nome `insecurity-inc-checkout-backend` → tags `project=insecurity-inc`, `env=lab`, `chapter=07` → **Create role**.
3. **Criar e anexar a policy:** **IAM** → **Policies** → **Create policy** → aba **JSON** → cole o JSON da policy da Opção 2 (substituindo região/conta/prefixo) → nome `insecurity-inc-checkout-backend-parameter-read` → **Create policy**. Volte para a role criada no passo 2 → aba **Permissions** → **Add permissions** → **Attach policies** → selecione a policy recém-criada → **Add permissions**.

## 🧾 Como testar

O objetivo é provar, na prática, quatro coisas: o fluxo legítimo de leitura funciona (com a diferença de comportamento entre `String` e `SecureString`); `GetParametersByPath` exige as duas entradas de `Resource` do ponto 3 da Correção; o isolamento por prefixo realmente bloqueia acesso a um parâmetro fora dele; e — o ponto central deste capítulo — a role decifra o `SecureString` sem ter nenhuma permissão de KMS na policy (passo 4), ou seja, com a chave padrão quem autoriza a leitura é o `ssm:GetParameter`, não um `kms:Decrypt` à parte.

Requer `jq` para ler as credenciais temporárias do `sts assume-role`.

```bash
ROLE_ARN=$(terraform output -raw checkout_backend_role_arn)

# Guardrail: avisa se ROLE_ARN ficou vazia (ou "None"). Sem ele, rodar o bloco
# fora da pasta do capítulo passa em branco: o "terraform output" não acha o
# state e a variável fica vazia sem erro.
[ -n "$ROLE_ARN" ] && [ "$ROLE_ARN" != None ] || echo "ROLE_ARN VAZIA -- não continue sem corrigir (rode dentro da pasta do capítulo e confira o login AWS)"

# 1. Assumir a role da aplicação de checkout
ASSUMED=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name checkout-backend-test)
# Guardrail: se o assume-role falhar, ASSUMED fica vazio, os "export" abaixo
# exportam credenciais vazias e a AWS CLI cai de volta na SUA identidade -- os
# próximos comandos rodariam como você, não como a role, e o teste mentiria
# (o passo 6, por exemplo, sobrescreveria o db_password de verdade).
[ -n "$ASSUMED" ] || echo "ASSUMED VAZIO -- o assume-role falhou; não continue: os próximos comandos rodariam como VOCÊ, não como a role"
export AWS_ACCESS_KEY_ID=$(echo "$ASSUMED" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUMED" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$ASSUMED" | jq -r .Credentials.SessionToken)

# 2. Feature flag (String) -- plaintext direto, sem flag nenhuma
aws ssm get-parameter --name /insecurity-inc/checkout/prod/feature_checkout_v2_enabled \
  --query 'Parameter.{Type:Type,Value:Value}'
# Esperado: Type "String", Value "false"

# 3. db_password (SecureString) SEM --with-decryption -- cifrado, ilegível
aws ssm get-parameter --name /insecurity-inc/checkout/prod/db_password \
  --query 'Parameter.{Type:Type,Value:Value}'
# Esperado: Value começando com "AQICAH..." -- um blob cifrado em base64, não a senha

# 4. db_password COM --with-decryption -- plaintext
aws ssm get-parameter --name /insecurity-inc/checkout/prod/db_password --with-decryption \
  --query 'Parameter.Value'
# Esperado: a senha de laboratório gerada pelo random_password.db_password --
# decifrada mesmo a role não tendo NENHUMA permissão de KMS na policy (ver
# Correção, ponto 5).

# 5. GetParametersByPath recursivo -- exige a entrada de Resource SEM "/*"
#    no final (ver Correção, ponto 3); com só ".../prod/*" isto voltaria
#    AccessDeniedException mesmo a role tendo acesso a cada parâmetro
#    individualmente.
aws ssm get-parameters-by-path --path /insecurity-inc/checkout/prod --recursive --with-decryption \
  --query 'Parameters[].{Name:Name,Type:Type}'
# Esperado: os três parâmetros deste capítulo

# 6. Tentar escrever -- negado, a role é só leitura
aws ssm put-parameter --name /insecurity-inc/checkout/prod/db_password \
  --value "hacked" --type SecureString --overwrite
# Esperado: AccessDeniedException em ssm:PutParameter

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# 7. Isolamento por prefixo: cria (como você mesmo, fora da role) um
#    parâmetro de "outro time", fora do prefixo do checkout
aws ssm put-parameter --name /insecurity-inc/security-team/prod/incident_webhook_url \
  --value "https://example.invalid/webhook" --type SecureString

ASSUMED=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name checkout-backend-test-isolation)
[ -n "$ASSUMED" ] || echo "ASSUMED VAZIO -- o assume-role falhou; não continue: os próximos comandos rodariam como VOCÊ, não como a role"
export AWS_ACCESS_KEY_ID=$(echo "$ASSUMED" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUMED" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$ASSUMED" | jq -r .Credentials.SessionToken)

aws ssm get-parameter --name /insecurity-inc/security-team/prod/incident_webhook_url --with-decryption
# Esperado: AccessDeniedException -- fora do prefixo do checkout, mesmo sendo
# a MESMA chave KMS padrão (alias/aws/ssm) usada pelos parâmetros do checkout.
# Isto é o que de fato isola os dois times: o escopo por prefixo da IAM
# policy, não a criptografia.

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
aws ssm delete-parameter --name /insecurity-inc/security-team/prod/incident_webhook_url
```

## 🧹 Como destruir

### 🏗️ Terraform

```bash
terraform destroy
```

> Sem janela de espera nem cobrança residual: parâmetros do Parameter Store e recursos IAM são apagados imediatamente, ao contrário da CMK do capítulo 06. Este capítulo não deixa nada "pendurado" depois do destroy.

### ⌨️ AWS CLI

```bash
PREFIX="/insecurity-inc/checkout/prod"

aws iam detach-role-policy --role-name insecurity-inc-checkout-backend --policy-arn "$POLICY_ARN"
aws iam delete-policy --policy-arn "$POLICY_ARN"
aws iam delete-role --role-name insecurity-inc-checkout-backend

aws ssm delete-parameter --name "${PREFIX}/db_password"
aws ssm delete-parameter --name "${PREFIX}/payment_gateway_api_key"
aws ssm delete-parameter --name "${PREFIX}/feature_checkout_v2_enabled"
```

### 🖥️ Console (GUI)

1. **IAM** → **Roles** → `insecurity-inc-checkout-backend` → aba **Permissions** → desanexe a policy → volte para **Roles** → selecione a role → **Delete**.
2. **IAM** → **Policies** → `insecurity-inc-checkout-backend-parameter-read` → **Actions** → **Delete**.
3. **Systems Manager** → **Parameter Store** → selecione os três parâmetros sob `/insecurity-inc/checkout/prod/` → **Delete**.

## 📚 Referências

- [SEC08-BP02 — Enforce encryption at rest](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_encrypt.html) — AWS Well-Architected Framework, Security Pillar; base da troca de `String` por `SecureString` neste capítulo.
- [SEC03-BP02 — Grant least privilege access](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_least_privileges.html) — mesmo princípio do capítulo 01, aqui violado por uma decisão de nomenclatura (ponto 2 do Problema) em vez de uma policy gerenciada ampla demais.
- [AWS KMS encryption for AWS Systems Manager Parameter Store SecureString parameters](https://docs.aws.amazon.com/systems-manager/latest/userguide/secure-string-parameter-kms-encryption.html) — fonte da citação oficial usada no ponto 5 da Correção: *"you cannot establish access control policies for the default aws/ssm KMS key"*.
- [Restricting access to Parameter Store parameters using IAM policies](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-paramstore-access.html) — referência oficial do escopo por prefixo via `Resource` usado neste capítulo, incluindo a observação de que acesso a um path superior implica acesso aos paths abaixo dele.
- [List of AWS Config Managed Rules](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html) — lista completa consultada para confirmar a ausência de uma regra gerenciada sobre criptografia de parâmetro (ponto 3 do Problema).
- [AWS Systems Manager Pricing](https://aws.amazon.com/systems-manager/pricing/) — parâmetros Standard com throughput padrão não têm custo adicional; base da nota de custo 🟢 deste capítulo.
- [Service Authorization Reference — AWS Systems Manager](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ssm.html#list_ssm-action-DescribeParameters) — confirma que `ssm:DescribeParameters` não suporta permissão a nível de recurso (ponto 4 da Correção), mesmo padrão citado para `ec2:DescribeInstances` no capítulo 01.
