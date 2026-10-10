# 08 — 🔏 Secrets Manager

![Capa do capítulo 08 — Secrets Manager](../imagens/cover-S01E08.jpg)

**Arco:** Dados  
**Conceito:** Secrets rotacionados  
**Well-Architected:** [SEC02-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_secrets.html)  
**Custo:** 🟡  

## 🎬 Cenário

O capítulo 07 arrumou *onde* a senha do banco de dados do checkout mora: agora é um `SecureString` sob `/insecurity-inc/checkout/prod/db_password`, cifrado, com uma IAM policy escopada ao prefixo. Numa revisão de segurança, a analista faz uma pergunta simples: **"quando foi a última vez que essa senha mudou?"**

Ninguém sabe responder de cabeça. Alguém abre o histórico do banco e a resposta é desconfortável: **nunca**. É a mesma senha do dia 1. A pessoa que a criou saiu da empresa há meses e continua com ela — no histórico de um chat, num bloco de notas, no notebook que devolveu (formatado, esperamos).

Ninguém trocou porque trocar dá trabalho, e o trabalho não é só a troca. O runbook manual é este:

```text
1. ALTER USER checkout_app WITH PASSWORD '<nova>';
   -- a partir daqui, toda instância do checkout perde a conexão com o banco
2. aws ssm put-parameter --name /insecurity-inc/checkout/prod/db_password \
     --value '<nova>' --type SecureString --overwrite
3. Reiniciar todas as instâncias do checkout, uma a uma
   -- a aplicação lê a senha uma vez, no boot, e a guarda na memória
```

Janela de manutenção, coordenação entre times, risco de derrubar o checkout em horário de pico. O item vira "rotacionar senha do banco (quando der)" no backlog — e o "quando der" nunca chega. Do lado da aplicação, o padrão que torna o passo 3 inevitável é este:

```bash
# user-data da instância: roda UMA vez, no boot. A senha fica na memória do
# processo pelo resto da vida dele -- trocá-la no banco derruba a aplicação.
export DB_PASSWORD=$(aws ssm get-parameter --name /insecurity-inc/checkout/prod/db_password \
  --with-decryption --query Parameter.Value --output text)
exec ./checkout-app
```

O `SecureString` do capítulo 07 protege a senha *em repouso*. Não diz nada sobre há quanto tempo ela está valendo.

## 🚨 O Problema

1. **Credencial de vida longa, sem rotação: a janela de exposição nunca fecha.** Uma senha que nunca muda vale para todo mundo que já a viu — quem saiu da empresa, um log, um backup de notebook, um chat — e vai continuar valendo. Rotacionar troca "vazou alguma vez" por "vazou nos últimos N dias". O [SEC02-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_secrets.html) pede exatamente isso: segredo num serviço dedicado, **com rotação**. O `SecureString` cifra, mas não rotaciona — a dívida que o capítulo 07 deixou declarada no final.
2. **A aplicação lê o segredo uma vez, no boot.** Enquanto a senha for um valor copiado para dentro do processo, rotacionar exige redeploy coordenado, e o custo desse redeploy é o motivo de a rotação nunca acontecer. Rotação só é viável se a aplicação consulta o segredo **pelo nome, em runtime**, e se durante a troca existe sobreposição entre o valor velho e o novo (os labels `AWSCURRENT` e `AWSPREVIOUS`, detalhados abaixo).
3. **A API não bloqueia resource policy pública por padrão.** `PutResourcePolicy` tem o parâmetro `BlockPublicPolicy`, cujo padrão é `false`: uma policy com `Principal: "*"` é aceita sem reclamar. Testado no passo 8 de Como testar.
4. **Existem controles detectivos, mas nenhum está ligado.** Ao contrário do Parameter Store (capítulo 07, que não tem nenhuma regra), o Secrets Manager tem cobertura de sobra: cinco [regras gerenciadas do AWS Config](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html) (`secretsmanager-rotation-enabled-check`, `secretsmanager-scheduled-rotation-success-check`, `secretsmanager-secret-periodic-rotation`, `secretsmanager-secret-unused`, `secretsmanager-using-cmk`), os controles [SecretsManager.1 a .5 do Security Hub](https://docs.aws.amazon.com/securityhub/latest/userguide/secretsmanager-controls.html) (rotação habilitada, rotação bem-sucedida, secret sem uso, rotacionado dentro de N dias — padrão 90 —, tags) e o [IAM Access Analyzer](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-resources.html), que analisa resource policies de secrets. Na Insecurity Inc. nada disso está ligado (o Config só chega no capítulo 12), então o erro passa batido.

## ✅ A Correção

1. **Um secret, não um parâmetro.** `insecurity-inc/checkout/prod/db-credentials`, com um JSON no formato dos templates oficiais de rotação de banco da AWS — `username`, `password`, `engine`, `host`, `port`, `dbname` —, para o dia em que este laboratório ganhar um banco de verdade. Mesmo prefixo hierárquico do capítulo 07, pelo mesmo motivo: dá algo comum para escopar a IAM policy.
2. **Rotação automática a cada 30 dias, feita por uma Lambda.** O Secrets Manager chama a função quatro vezes por rotação e usa *staging labels* para nunca deixar o secret sem uma versão válida no meio do caminho:

   | Etapa | O que faz | Neste laboratório |
   | --- | --- | --- |
   | `createSecret` | Gera a senha nova (`GetRandomPassword`) e a grava numa versão nova, com o label `AWSPENDING`. Idempotente: se a rotação falhar adiante e o serviço tentar de novo, reaproveita a versão. | **Real** |
   | `setSecret` | Troca a senha no banco para a do `AWSPENDING`. Antes, uma guarda de *confused deputy* (recomendação da AWS): só age se `AWSCURRENT` e `AWSPENDING` apontam para o **mesmo** `username` e `host`. | **Stub** |
   | `testSecret` | Conecta no banco com a senha nova, antes de promovê-la. Se falhar, a rotação aborta e a aplicação nunca vê uma senha ruim. | **Stub** (só valida o formato) |
   | `finishSecret` | Move `AWSCURRENT` para a versão nova; a antiga vira `AWSPREVIOUS` (último valor bom conhecido). | **Real** |

   > **Limitação deliberada — leia antes de tirar conclusões.** Não existe banco de dados neste capítulo. Um RDS quebraria a restrição de custo do projeto e exigiria VPC, que só entra no arco de Rede (capítulo 09). Por isso `setSecret` e `testSecret` são *stubs*: registram o que fariam e validam o formato, mas não tocam em banco nenhum.  
   O laboratório prova a **mecânica** da rotação — agendamento, versões, labels, permissões, leitura em runtime —, não a troca de senha num banco. Num banco real, é o `setSecret` que faz a senha antiga (a que a pessoa que saiu ainda conhece) deixar de funcionar. Para bancos suportados, a AWS publica funções prontas ([templates de rotação](https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html)) que fazem essas duas etapas de verdade; o esqueleto de [rotation.py](./lambda/rotation.py) segue o mesmo protocolo.

   `rotate_immediately = true`: a primeira rotação roda **já no `apply`**. A "senha do dia 1", gravada pelo Terraform, deixa de ser `AWSCURRENT` em segundos — passo 3 de Como testar.
3. **A aplicação lê pelo nome, em runtime.** `GetSecretValue` sem parâmetro de versão devolve `AWSCURRENT`. A aplicação só precisa conhecer o **nome** do secret — nenhum valor, nenhum redeploy. Testado no passo 4: a mesma chamada, sem mudar configuração nenhuma, devolveu uma senha diferente depois da rotação. Numa aplicação real, o cliente deve guardar o valor em cache com TTL curto (a AWS publica clientes de cache oficiais) e rebuscar o secret quando a autenticação falhar.
4. **Role de leitura: uma action, um ARN.** A role `insecurity-inc-checkout-backend` (a mesma do capítulo 07, agora lendo do Secrets Manager) só tem `secretsmanager:GetSecretValue`, e só no ARN **completo** deste secret. O ARN de um secret tem um sufixo aleatório de 6 caracteres depois do nome (`...db-credentials-PrbmwM`); usar o ARN inteiro, em vez de um padrão como `secret:insecurity-inc/checkout/prod/db-credentials*`, evita casar por acidente um secret irmão cujo nome comece igual. Sem `DescribeSecret`, `PutSecretValue` nem `RotateSecret`: quem grava valor novo é a Lambda de rotação, e a aplicação nunca precisa saber a agenda.
5. **A Lambda de rotação também tem privilégio mínimo.** Sua role (`insecurity-inc-checkout-db-rotation`) tem as quatro actions da rotação (`DescribeSecret`, `GetSecretValue`, `PutSecretValue`, `UpdateSecretVersionStage`) **só neste secret**, `GetRandomPassword` com `Resource: "*"` (a action não opera sobre recurso nenhum) e escrita de logs **só no próprio log group**. A permissão que deixa o Secrets Manager invocar a função usa `aws:SourceAccount` — a [recomendação oficial](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_turn-on-for-other.html) contra *confused deputy*; a mesma doc recomenda **não** usar `aws:SourceArn` junto quando a função pode servir a mais de um secret, porque a amarraria a um só. O log group é criado explicitamente, com retenção de 7 dias: se a Lambda o criasse sozinha no primeiro uso, ele nasceria com retenção infinita (custo esquecido que só cresce).
6. **Chave padrão `aws/secretsmanager`, nenhuma statement de KMS — de propósito.** Mesma decisão e mesmo motivo do capítulo 07: uma CMK custaria ~US$1/mês (capítulo 06) e fugiria do escopo 🟡 deste capítulo, que é só o secret. Testado: a role do checkout, sem **nenhuma** permissão de KMS na policy, lê e decifra o secret (passo 3). A [documentação](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets-required-permissions-function.html) só exige conceder KMS ao execution role da Lambda de rotação quando o secret usa uma chave *diferente* da `aws/secretsmanager` — e nesse caso sugere limitar o `kms:Decrypt` com o encryption context `kms:EncryptionContext:SecretARN`.
7. **A senha inicial nunca toca o state.** No capítulo 07 os `random_password` comuns deixaram as senhas em texto claro no `terraform.tfstate`. Aqui, num capítulo sobre segredos, seria repetir o erro: a senha do dia 1 é um `ephemeral "random_password"` (existe só durante o `apply`) gravada via `secret_string_wo`, um atributo *write-only* (o Terraform envia o valor à API e não o guarda). O `plan` mostra `secret_string_wo = (write-only attribute)` e, no state, `secret_string` fica vazio (passo 9). Efeito colateral bom: como o Terraform não guarda o valor, também não o enxerga como deriva quando a rotação o troca — `terraform plan` depois de rotações sai com **"No changes"**. Custo: este capítulo exige Terraform ≥ 1.11 e provider AWS ≥ 5.100.
8. **Resource policy: nenhuma, e por quê.** Na mesma conta, a identity policy da role já concede o acesso; uma resource policy só se faz necessária para acesso entre contas. Este capítulo não anexa nenhuma. Mas o Problema 3 continua valendo para quem anexar: sempre com `--block-public-policy` (CLI) ou `block_public_policy = true` (recurso `aws_secretsmanager_secret_policy`). Exigir isso de **todo mundo** é trabalho de um guardrail organizacional (SCP, capítulo 14).

**Dívidas em aberto.** Rotação sem detecção não fecha o ciclo: nada avisa se a rotação passar a falhar (a regra `secretsmanager-scheduled-rotation-success-check` cobre isso — capítulos 12 e 13), nem quem leu o secret (o CloudTrail registra `GetSecretValue` — capítulo 11). E a rotação de **usuário único**, a que este capítulo modela, pode deixar uma janela curta em que quem ainda segura a senha antiga vê falha de autenticação até rebuscar o secret; a estratégia de *alternating users* evita isso — ver [Lambda function rotation strategies](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html).

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar.

> **Pré-requisito:** o capítulo 07 precisa estar destruído — ele usa o mesmo nome de role (`insecurity-inc-checkout-backend`).
>
> **Custo:** US$0,40 por secret por mês, [proporcional às horas](https://aws.amazon.com/secrets-manager/pricing/) de vida do secret (~US$0,00056 por hora), mais US$0,05 por 10 mil chamadas de API. Este laboratório vive minutos: o custo real é fração de centavo. A Lambda (poucas invocações de centenas de milissegundos) e os logs (retenção de 7 dias) não têm custo perceptível.

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

Requer Terraform ≥ 1.11. A rotação inicial dispara ainda dentro do `apply` (`rotate_immediately`); ela é assíncrona, então leva alguns segundos para terminar depois que o comando volta.

### ⌨️ Opção 2 — AWS CLI

Rode dentro da pasta do capítulo: o passo 4 usa o arquivo `lambda/rotation.py`, e precisa do `zip` e do `jq` instalados.

```bash
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
for v in REGION ACCOUNT_ID CALLER_ARN; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (confira o login AWS e o 'aws configure')"; done

SECRET_NAME="insecurity-inc/checkout/prod/db-credentials"
FUNCTION_NAME="insecurity-inc-checkout-db-rotation"
TAGS_KV="Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=08"

# 1. O secret, com a "senha do dia 1" gerada na hora -- nunca hardcode um valor
#    num comando de shell (fica no histórico do terminal). O JSON vai para um
#    arquivo temporário só do seu usuário (umask 077) e é apagado logo depois,
#    para o valor não aparecer na lista de processos (ps) nem no histórico.
DB_PASSWORD=$(aws secretsmanager get-random-password --password-length 24 --exclude-punctuation --query RandomPassword --output text)
[ -n "$DB_PASSWORD" ] && [ "$DB_PASSWORD" != None ] || echo "DB_PASSWORD VAZIA -- não continue sem corrigir (o get-random-password falhou; confira o login AWS)"
SECRET_FILE=$(umask 077; mktemp)
jq -n --arg p "$DB_PASSWORD" '{username:"checkout_app", password:$p, engine:"postgres", host:"checkout-db.insecurity-inc.invalid", port:5432, dbname:"checkout"}' > "$SECRET_FILE"

SECRET_ARN=$(aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Credenciais do banco de dados do checkout (dado de laboratório -- não existe banco real neste capítulo). Rotacionado automaticamente." \
  --secret-string "file://$SECRET_FILE" \
  --tags $TAGS_KV \
  --query ARN --output text)
[ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != None ] || echo "SECRET_ARN VAZIA -- não continue sem corrigir (o create-secret falhou)"
rm -f "$SECRET_FILE"; unset DB_PASSWORD

# 2. Log group da Lambda, criado antes dela e com retenção de 7 dias (se a
#    Lambda o criasse sozinha, nasceria com retenção infinita).
aws logs create-log-group --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
  --tags project=insecurity-inc,env=lab,chapter=08
aws logs put-retention-policy --log-group-name "/aws/lambda/${FUNCTION_NAME}" --retention-in-days 7

# 3. Role de execução da Lambda de rotação: só este secret, só o próprio log group.
cat > /tmp/rotation-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

cat > /tmp/rotation-permissions.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RotateOnlyThisSecret",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecretVersionStage"
      ],
      "Resource": "${SECRET_ARN}"
    },
    {
      "Sid": "GenerateRandomPasswordRequiresWildcardResource",
      "Effect": "Allow",
      "Action": "secretsmanager:GetRandomPassword",
      "Resource": "*"
    },
    {
      "Sid": "WriteOwnLogsOnly",
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/lambda/${FUNCTION_NAME}:*"
    }
  ]
}
EOF

aws iam create-role \
  --role-name insecurity-inc-checkout-db-rotation \
  --assume-role-policy-document file:///tmp/rotation-trust.json \
  --description "Execution role da Lambda que rotaciona o secret de credenciais do banco do checkout -- escopada só a este secret." \
  --tags $TAGS_KV

aws iam put-role-policy \
  --role-name insecurity-inc-checkout-db-rotation \
  --policy-name rotate-checkout-db-credentials \
  --policy-document file:///tmp/rotation-permissions.json

# 4. A Lambda de rotação. O sleep dá tempo de o IAM propagar a role nova; sem
#    ele, o create-function pode falhar com "The role defined for the function
#    cannot be assumed by Lambda".
(cd lambda && zip -q ../rotation.zip rotation.py)
sleep 10

aws lambda create-function \
  --function-name "$FUNCTION_NAME" \
  --description "Rotaciona o secret ${SECRET_NAME} (protocolo de 4 etapas; setSecret/testSecret são stubs -- sem banco neste lab)." \
  --role "arn:aws:iam::${ACCOUNT_ID}:role/insecurity-inc-checkout-db-rotation" \
  --runtime python3.12 --handler rotation.lambda_handler \
  --architectures arm64 --timeout 30 --memory-size 128 \
  --zip-file fileb://rotation.zip \
  --tags project=insecurity-inc,env=lab,chapter=08
aws lambda wait function-active-v2 --function-name "$FUNCTION_NAME"

# 5. Deixa o Secrets Manager (só o desta conta) invocar a função. Só
#    aws:SourceAccount, sem SourceArn -- ver Correção, ponto 5.
aws lambda add-permission \
  --function-name "$FUNCTION_NAME" \
  --statement-id AllowSecretsManagerInvoke \
  --action lambda:InvokeFunction \
  --principal secretsmanager.amazonaws.com \
  --source-account "$ACCOUNT_ID"

# 6. Liga a rotação (30 dias) e dispara a primeira já -- a senha do dia 1 é
#    substituída em segundos.
aws secretsmanager rotate-secret \
  --secret-id "$SECRET_NAME" \
  --rotation-lambda-arn "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}" \
  --rotation-rules AutomaticallyAfterDays=30 \
  --rotate-immediately

# 7. Role da aplicação de checkout -- trust simplificado para a própria
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

cat > /tmp/checkout-backend-secret-read.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "ReadCheckoutDbCredentials",
    "Effect": "Allow",
    "Action": "secretsmanager:GetSecretValue",
    "Resource": "${SECRET_ARN}"
  }]
}
EOF

aws iam create-role \
  --role-name insecurity-inc-checkout-backend \
  --assume-role-policy-document file:///tmp/checkout-backend-trust.json \
  --description "Role da aplicação de checkout -- aqui, escopada só à leitura do secret de credenciais do banco." \
  --tags $TAGS_KV

POLICY_ARN=$(aws iam create-policy \
  --policy-name insecurity-inc-checkout-backend-secret-read \
  --description "Leitura (não escrita, não rotação) do secret ${SECRET_NAME} -- não de todos os secrets da conta." \
  --policy-document file:///tmp/checkout-backend-secret-read.json \
  --query Policy.Arn --output text)

aws iam attach-role-policy \
  --role-name insecurity-inc-checkout-backend \
  --policy-arn "$POLICY_ARN"

rm -f /tmp/rotation-trust.json /tmp/rotation-permissions.json /tmp/checkout-backend-trust.json /tmp/checkout-backend-secret-read.json rotation.zip
```

### 🖥️ Opção 3 — Console (GUI)

1. **Criar o secret:** console **Secrets Manager** → **Store a new secret** → tipo **Other type of secret** → aba **Plaintext** → cole um JSON como `{"username":"checkout_app","password":"<uma senha qualquer de laboratório>","engine":"postgres","host":"checkout-db.insecurity-inc.invalid","port":5432,"dbname":"checkout"}` → **Encryption key:** deixe `aws/secretsmanager` (a padrão) → **Next** → nome `insecurity-inc/checkout/prod/db-credentials` → tags `project=insecurity-inc`, `env=lab`, `chapter=08` → **Next** → **não** configure a rotação ainda → **Next** → **Store**.
2. **Criar a Lambda de rotação:** console **Lambda** → **Create function** → **Author from scratch** → nome `insecurity-inc-checkout-db-rotation`, runtime **Python 3.12**, arquitetura **arm64** → em **Change default execution role**, deixe criar uma role nova (você ajusta as permissões no passo 3) → **Create function**. Na aba **Code**, cole o conteúdo de [lambda/rotation.py](./lambda/rotation.py) no arquivo `lambda_function.py` (o handler padrão, `lambda_function.lambda_handler`, funciona — no Terraform o arquivo se chama `rotation.py` e o handler é `rotation.lambda_handler`; é só nome) → **Deploy**. Em **Configuration** → **General configuration**, mude o **Timeout** para 30 s. Em **Configuration** → **Monitoring and operations tools**, mantenha o log group padrão (`/aws/lambda/insecurity-inc-checkout-db-rotation`) e depois, em **CloudWatch** → **Log groups**, ajuste a **Retention** para 7 dias.
3. **Ajustar a role da Lambda:** em **Configuration** → **Permissions**, abra a role de execução e troque a policy gerada por uma **inline policy** com o JSON `/tmp/rotation-permissions.json` da Opção 2 (substituindo `${SECRET_ARN}`, região, conta e nome da função). O objetivo é que ela tenha só o que está naquele JSON: as quatro actions no ARN do secret, `GetRandomPassword` em `*` e escrita no próprio log group.
4. **Deixar o Secrets Manager invocar a função — antes de ligar a rotação:** na Lambda, **Configuration** → **Permissions** → **Resource-based policy statements** → **Add permissions** → **AWS service** → serviço **Secrets Manager**, Statement ID `AllowSecretsManagerInvoke`, action `lambda:InvokeFunction`, e em **Source account** a sua conta → **Save**.
5. **Ligar a rotação:** **Secrets Manager** → o secret → aba **Rotation** → **Edit rotation** → **Automatic rotation** ligado, schedule de **30 dias**, marque **Rotate immediately when the secret is stored**, escolha a Lambda `insecurity-inc-checkout-db-rotation` → **Save**.
6. **Criar a role da aplicação:** console **IAM** → **Roles** → **Create role** → **Custom trust policy** → cole a trust policy do passo 7 da Opção 2 (com o ARN da sua própria identidade) → **Next** → sem policy gerenciada por enquanto → nome `insecurity-inc-checkout-backend` → tags `project=insecurity-inc`, `env=lab`, `chapter=08` → **Create role**.
7. **Criar e anexar a policy de leitura:** **IAM** → **Policies** → **Create policy** → aba **JSON** → cole o JSON da policy do passo 7 da Opção 2 (com o ARN completo do secret, que aparece nos detalhes do secret) → nome `insecurity-inc-checkout-backend-secret-read` → **Create policy**. Volte para a role do passo 6 → aba **Permissions** → **Add permissions** → **Attach policies** → selecione a policy → **Add permissions**.

## 🧾 Como testar

O objetivo é provar, na prática, cinco coisas: a rotação já rodou e a "senha do dia 1" já é passado (passos 1 a 3); a aplicação, **sem mudar nada**, passa a receber a senha nova depois de uma rotação (passo 4); a role só lê **este** secret, e só lê (passos 5 e 6); a rotação **não** apaga o acesso ao histórico (passo 7); e a API só bloqueia policy pública se você pedir (passo 8). O passo 9 confirma que a senha não vazou para o state.

Requer `jq`. Nos exemplos, o hash da senha (`sha256sum`) substitui o valor: comparar hashes prova que a senha mudou sem imprimir a senha. No macOS, troque `sha256sum` por `shasum -a 256`.

```bash
SECRET_ID=$(terraform output -raw secret_name)
ROLE_ARN=$(terraform output -raw checkout_backend_role_arn)

# Guardrail: avisa se alguma variável ficou vazia (ou "None"). Sem ele, rodar o
# bloco fora da pasta do capítulo passa em branco: o "terraform output" não acha
# o state e as variáveis ficam vazias sem erro.
for v in SECRET_ID ROLE_ARN; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (rode dentro da pasta do capítulo e confira o login AWS)"; done

# Simula a aplicação: assume a role e roda o comando que vier depois. Roda num
# subshell, então as credenciais da role NÃO vazam para o seu shell -- os
# comandos "de admin" entre um teste e outro continuam sendo seus.
app_read() {
  local ASSUMED
  ASSUMED=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name checkout-backend-test)
  # Guardrail: se o assume-role falhar, ASSUMED fica vazio, os "export" abaixo
  # exportam credenciais vazias e a AWS CLI cai de volta na SUA identidade -- o
  # teste rodaria como você, não como a role, e mentiria.
  [ -n "$ASSUMED" ] || { echo "ASSUMED VAZIO -- o assume-role falhou; não continue: os próximos comandos rodariam como VOCÊ, não como a role"; return 1; }
  (
    export AWS_ACCESS_KEY_ID=$(echo "$ASSUMED" | jq -r .Credentials.AccessKeyId)
    export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUMED" | jq -r .Credentials.SecretAccessKey)
    export AWS_SESSION_TOKEN=$(echo "$ASSUMED" | jq -r .Credentials.SessionToken)
    "$@"
  )
}

# Lê a senha de um secret (JSON no stdin) e devolve só o hash dela.
pw_hash() { jq -r .password | sha256sum | cut -c1-12; }

# 0. Pré-condição: estado vivo == Terraform, e nenhuma resource policy pendurada.
#    (O passo 8 muda a resource policy do secret e reverte; um teste interrompido
#    no meio deixaria o secret exposto, e o resto dos resultados mentiria.)
terraform plan -detailed-exitcode > /dev/null; echo "plan exit=$?  (0 = sem deriva; 2 = há deriva: corrija antes de testar)"
aws secretsmanager get-resource-policy --secret-id "$SECRET_ID" --query ResourcePolicy --output text
# Esperado: exit=0, e "None" na segunda linha

# 1. Estado da rotação
aws secretsmanager describe-secret --secret-id "$SECRET_ID" \
  --query '{RotationEnabled:RotationEnabled,Rules:RotationRules,LastRotatedDate:LastRotatedDate,NextRotationDate:NextRotationDate,KmsKeyId:KmsKeyId,Versions:VersionIdsToStages}'
# Esperado: RotationEnabled true, AutomaticallyAfterDays 30, NextRotationDate
# ~30 dias à frente, KmsKeyId null (null = a chave padrão aws/secretsmanager) e
# DUAS versões: a do dia 1 (gravada pelo Terraform) só com AWSPREVIOUS, e a
# criada pela rotação do apply com AWSCURRENT. Ver ao lado dela o AWSPENDING é
# normal: depois de uma rotação bem-sucedida, o label pode ficar preso à mesma
# versão que virou AWSCURRENT. Só sinaliza rotação incompleta se estiver numa
# versão DIFERENTE da AWSCURRENT.

# 2. O que a Lambda fez -- as quatro etapas, e nenhuma senha nos logs
aws logs tail /aws/lambda/insecurity-inc-checkout-db-rotation --since 1h --format short | grep -E '(create|set|test|finish)Secret:'
# Esperado: createSecret ("nova versão ... gravada como AWSPENDING"), setSecret
# ("(stub, sem banco neste lab) trocaria a senha de 'checkout_app' em ..."),
# testSecret ("(stub ...) formato de AWSPENDING validado") e finishSecret
# ("AWSCURRENT movido da versão ... para ..."). Só ARN, etapa e id de versão.

# 3. A aplicação lê o secret -- a role NÃO tem nenhuma permissão de KMS
CUR_HASH=$(app_read aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text | pw_hash)
PREV_HASH=$(app_read aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --version-stage AWSPREVIOUS --query SecretString --output text | pw_hash)
for v in CUR_HASH PREV_HASH; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIO -- a leitura como a role falhou; não continue"; done
echo "AWSCURRENT:  $CUR_HASH"
echo "AWSPREVIOUS: $PREV_HASH"
# Esperado: dois hashes DIFERENTES. O AWSPREVIOUS é a "senha do dia 1", e a
# rotação do apply já a substituiu. A leitura funcionou sem nenhuma permissão de
# KMS na policy da role: com a chave aws/secretsmanager, o que autoriza a leitura
# é o próprio secretsmanager:GetSecretValue (mesmo padrão do capítulo 07).

# 4. Força uma segunda rotação -- a aplicação, sem mudar nada, recebe a senha nova
BEFORE_ID=$(aws secretsmanager describe-secret --secret-id "$SECRET_ID" --query VersionIdsToStages --output json | jq -r 'to_entries[] | select(.value|index("AWSCURRENT")) | .key')
aws secretsmanager rotate-secret --secret-id "$SECRET_ID"
for i in $(seq 1 12); do
  sleep 5
  NOW_ID=$(aws secretsmanager describe-secret --secret-id "$SECRET_ID" --query VersionIdsToStages --output json | jq -r 'to_entries[] | select(.value|index("AWSCURRENT")) | .key')
  [ "$NOW_ID" != "$BEFORE_ID" ] && { echo "rotação concluída após ~$((i*5))s"; break; }
done
aws secretsmanager describe-secret --secret-id "$SECRET_ID" --query VersionIdsToStages --output json
echo "app lê AWSCURRENT:  $(app_read aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text | pw_hash)"
echo "app lê AWSPREVIOUS: $(app_read aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --version-stage AWSPREVIOUS --query SecretString --output text | pw_hash)"
# Esperado: a rotação conclui em segundos; a versão nova tem AWSCURRENT, a que
# era AWSCURRENT virou AWSPREVIOUS, e a "do dia 1" ficou sem label nenhum (some
# do describe-secret). O hash do AWSCURRENT é DIFERENTE do passo 3 -- mesma
# chamada, mesmo código, sem redeploy nem configuração nova. O do AWSPREVIOUS é
# igual ao CUR_HASH do passo 3. Também prova que o AWSPENDING remanescente do
# passo 1 não travou a rotação seguinte.

# 5. Escritas negadas -- a role só lê
app_read aws secretsmanager put-secret-value --secret-id "$SECRET_ID" --secret-string '{"username":"hacked","password":"hacked"}'
app_read aws secretsmanager rotate-secret --secret-id "$SECRET_ID"
app_read aws secretsmanager describe-secret --secret-id "$SECRET_ID"
# Esperado: AccessDeniedException nos três (PutSecretValue, RotateSecret e
# DescribeSecret), "because no identity-based policy allows the ... action".

# 6. Isolamento: cria (como você mesmo, fora da role) um secret de "outro time"
aws secretsmanager create-secret --name insecurity-inc/security-team/prod/incident-webhook \
  --secret-string 'https://example.invalid/webhook' --query Name --output text
app_read aws secretsmanager get-secret-value --secret-id insecurity-inc/security-team/prod/incident-webhook
# Esperado: AccessDeniedException -- o secret está sob o mesmo prefixo raiz
# "insecurity-inc/", mas a policy da role cita o ARN completo de db-credentials,
# não um padrão de prefixo.
aws secretsmanager delete-secret --secret-id insecurity-inc/security-team/prod/incident-webhook --force-delete-without-recovery

# 7. Pegadinha: a rotação NÃO revoga o acesso às versões antigas
OLD_ID=$(aws secretsmanager list-secret-version-ids --secret-id "$SECRET_ID" --include-deprecated --query 'Versions[?VersionStages==`null`].VersionId | [0]' --output text)
[ -n "$OLD_ID" ] && [ "$OLD_ID" != None ] || echo "OLD_ID VAZIO -- não achou versão deprecada (rode o passo 4 antes)"
app_read aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --version-id "$OLD_ID" --query '{Stages:VersionStages,Version:VersionId}'
# Esperado: FUNCIONA -- Stages null, versão devolvida. Uma versão sem label
# ("deprecada") continua legível por VersionId até o Secrets Manager apagá-la.
# Com um banco real isso é inofensivo (o setSecret já matou aquela senha no
# banco), mas mostra que o que protege o histórico é só a IAM policy.

# 8. BlockPublicPolicy -- muda a resource policy do secret e REVERTE no fim
PUBLIC='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"secretsmanager:GetSecretValue","Resource":"*"}]}'

# 8a. Policy pública COM --block-public-policy
aws secretsmanager put-resource-policy --secret-id "$SECRET_ID" --resource-policy "$PUBLIC" --block-public-policy
# Esperado: PublicPolicyException -- "You can not attach a resource policy that
# grants Public access to your secret."

# 8b. Policy com principal específico (a role do checkout), também COM a flag
SCOPED=$(jq -nc --arg r "$ROLE_ARN" '{Version:"2012-10-17",Statement:[{Effect:"Allow",Principal:{AWS:$r},Action:"secretsmanager:GetSecretValue",Resource:"*"}]}')
aws secretsmanager put-resource-policy --secret-id "$SECRET_ID" --resource-policy "$SCOPED" --block-public-policy
# Esperado: aceita (devolve ARN e Name) -- a flag só barra acesso amplo.

# 8c. A MESMA policy pública, SEM a flag (o padrão da API é block-public-policy=false)
aws secretsmanager put-resource-policy --secret-id "$SECRET_ID" --resource-policy "$PUBLIC"
aws secretsmanager get-resource-policy --secret-id "$SECRET_ID" --query ResourcePolicy --output text | jq -c '.Statement[] | {Effect,Principal,Action}'
# Esperado: ACEITA. O secret ficou com Principal "*" -- de novo, o Problema 3.
# (Aqui o estrago é contido: a chave aws/secretsmanager não permite decifrar a
# partir de outra conta. Com uma policy dessas, mais uma CMK mal configurada,
# seria outra história.)

# REVERT -- sempre, mesmo se algum passo acima falhou:
aws secretsmanager delete-resource-policy --secret-id "$SECRET_ID"
aws secretsmanager get-resource-policy --secret-id "$SECRET_ID" --query ResourcePolicy --output text
# Esperado: "None" na última linha

# 9. A senha vazou para o state? E o Terraform brigou com a rotação?
CUR_PW=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --query SecretString --output text | jq -r .password)
[ -n "$CUR_PW" ] && [ "$CUR_PW" != None ] || echo "CUR_PW VAZIA -- não continue sem corrigir (confira o login AWS)"
grep -qF -- "$CUR_PW" terraform.tfstate && echo "!!! senha atual ENCONTRADA no tfstate" || echo "ok: a senha atual não está no tfstate"
unset CUR_PW
terraform plan -detailed-exitcode > /dev/null; echo "plan exit=$?  (0 = sem mudanças, mesmo depois de duas rotações e de mexer na resource policy)"
```

### 🖥️ Repetindo os testes 1 e 4 — Console (GUI)

**Secrets Manager** → o secret. A aba **Rotation** mostra a agenda (30 dias) e a data da última rotação; a aba **Versions** lista cada versão com seus *staging labels* — dá para ver `AWSCURRENT`/`AWSPREVIOUS` trocarem de lugar. Para o passo 4, o botão **Rotate secret immediately**, na aba **Rotation**, faz o mesmo que `rotate-secret`. Os logs das quatro etapas ficam em **CloudWatch** → **Log groups** → `/aws/lambda/insecurity-inc-checkout-db-rotation`.

## 🧹 Como destruir

### 🏗️ Terraform

```bash
terraform destroy
```

> O `recovery_window_in_days = 0` (padrão de `var.secret_recovery_window_in_days`) faz o secret ser apagado **na hora**, sem janela de recuperação. É o correto para um laboratório que faz apply/destroy/apply: com uma janela maior que zero, o nome do secret fica reservado até a deleção efetiva, e o próximo `apply` falha com `InvalidRequestException: You can't create this secret because a secret with this name is already scheduled for deletion` (testado). Em produção, mantenha 7 a 30 dias como rede de segurança contra deleção acidental — e sem custo: a [documentação](https://docs.aws.amazon.com/secretsmanager/latest/userguide/manage_delete-secret.html) é explícita: *"There is no charge for secrets that you have marked for deletion."* Diferente da CMK do capítulo 06, este capítulo não deixa nada cobrando depois do destroy.
>
> O arquivo `rotation.zip`, gerado pelo `data "archive_file"`, fica na pasta do capítulo, mas está no `.gitignore`.

Depois do destroy, confira que não sobrou nada (a listagem do Secrets Manager é eventualmente consistente: um secret recém-apagado pode continuar aparecendo por alguns segundos, tipicamente uns 20):

```bash
aws secretsmanager list-secrets --include-planned-deletion --filters Key=name,Values=insecurity-inc --query 'SecretList[].Name' --output text
aws lambda list-functions --query "Functions[?starts_with(FunctionName,'insecurity-inc')].FunctionName" --output text
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/insecurity-inc --query 'logGroups[].logGroupName' --output text
aws iam list-roles --query "Roles[?starts_with(RoleName,'insecurity-inc-checkout')].RoleName" --output text
# Esperado: as quatro saídas vazias
```

### ⌨️ AWS CLI

```bash
SECRET_NAME="insecurity-inc/checkout/prod/db-credentials"
FUNCTION_NAME="insecurity-inc-checkout-db-rotation"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/insecurity-inc-checkout-backend-secret-read"

# 1. Role e policy da aplicação
aws iam detach-role-policy --role-name insecurity-inc-checkout-backend --policy-arn "$POLICY_ARN"
aws iam delete-policy --policy-arn "$POLICY_ARN"
aws iam delete-role --role-name insecurity-inc-checkout-backend

# 2. O secret -- apagar o secret também remove a configuração de rotação.
#    --force-delete-without-recovery: sem janela, pelo mesmo motivo do Terraform.
aws secretsmanager delete-secret --secret-id "$SECRET_NAME" --force-delete-without-recovery

# 3. A Lambda, a role dela e o log group (delete-function NÃO apaga o log group)
aws lambda delete-function --function-name "$FUNCTION_NAME"
aws iam delete-role-policy --role-name insecurity-inc-checkout-db-rotation --policy-name rotate-checkout-db-credentials
aws iam delete-role --role-name insecurity-inc-checkout-db-rotation
aws logs delete-log-group --log-group-name "/aws/lambda/${FUNCTION_NAME}"
```

### 🖥️ Console (GUI)

1. **IAM** → **Roles** → `insecurity-inc-checkout-backend` → aba **Permissions** → desanexe a policy → volte para **Roles** → selecione a role → **Delete**.
2. **IAM** → **Policies** → `insecurity-inc-checkout-backend-secret-read` → **Actions** → **Delete**.
3. **Secrets Manager** → o secret `insecurity-inc/checkout/prod/db-credentials` → **Actions** → **Delete secret** → em **Waiting period**, o mínimo do console é 7 dias (não há custo durante a janela, mas o nome fica reservado). Para apagar na hora, use a Opção AWS CLI (`--force-delete-without-recovery`).
4. **Lambda** → **Functions** → `insecurity-inc-checkout-db-rotation` → **Actions** → **Delete function**.
5. **CloudWatch** → **Log groups** → `/aws/lambda/insecurity-inc-checkout-db-rotation` → **Actions** → **Delete log group(s)**.
6. **IAM** → **Roles** → `insecurity-inc-checkout-db-rotation` → **Delete**.

## 📚 Referências

- [SEC02-BP03 — Store and use secrets securely](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_secrets.html) — AWS Well-Architected Framework, Security Pillar; base do capítulo: segredo em serviço dedicado, com rotação.
- [Rotate AWS Secrets Manager secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html) — visão geral da rotação; distingue rotação gerenciada, de *managed external secrets* e por Lambda (a deste capítulo).
- [Lambda rotation functions](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_lambda-functions.html) — o protocolo de quatro etapas, os *staging labels* e a guarda de *confused deputy* do `setSecret` implementada neste capítulo.
- [Lambda rotation function execution role permissions](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets-required-permissions-function.html) — a policy de privilégio mínimo da role da Lambda, e a nota sobre KMS quando o secret usa uma chave diferente da `aws/secretsmanager`.
- [Set up automatic rotation for non-database secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_turn-on-for-other.html) — fonte da recomendação de `aws:SourceAccount` (sem `aws:SourceArn`) na permissão de invocação da Lambda.
- [Lambda function rotation strategies](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotation-strategy.html) — usuário único vs. *alternating users*, citado nas dívidas em aberto.
- [Delete an AWS Secrets Manager secret](https://docs.aws.amazon.com/secretsmanager/latest/userguide/manage_delete-secret.html) — janela de recuperação, `--force-delete-without-recovery` e a frase sobre não cobrar secret marcado para deleção.
- [PutResourcePolicy (API Reference)](https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_PutResourcePolicy.html) — o parâmetro `BlockPublicPolicy` (padrão `false`) e o `PublicPolicyException` testados no passo 8.
- [Security Hub CSPM controls for Secrets Manager](https://docs.aws.amazon.com/securityhub/latest/userguide/secretsmanager-controls.html) — SecretsManager.1 a .5, com as regras do Config por trás de cada um (ponto 4 do Problema).
- [List of AWS Config Managed Rules](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html) — lista consultada para confirmar as cinco regras `secretsmanager-*`.
- [IAM Access Analyzer — supported resource types](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-resources.html) — confirma que o analisador de acesso externo cobre secrets do Secrets Manager.
- [AWS Secrets Manager Pricing](https://aws.amazon.com/secrets-manager/pricing/) — US$0,40 por secret por mês e US$0,05 por 10 mil chamadas de API, com prorrateio por hora para secrets de vida curta; base da nota de custo 🟡 deste capítulo.
