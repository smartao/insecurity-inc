# 06 — 🗝️ KMS

![Capa do capítulo 06 — KMS](../imagens/cover-S01E06.jpg)

**Arco:** Dados  
**Conceito:** Encryption + Key Policy  
**Well-Architected:** [SEC08-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_key_mgmt.html)  
**Custo:** 🟡  

## 🎬 Cenário

O capítulo 05 fechou a porta do bucket de recibos — privado, TLS obrigatório, SSE-S3 por padrão — mas terminou com uma dívida em aberto: trocar a chave gerenciada pela AWS (SSE-S3) por uma chave gerenciada pelo cliente (SSE-KMS), a única forma de ganhar controle e auditoria *independentes* sobre quem decifra os recibos. O time de segurança da Insecurity Inc. finalmente cobra essa dívida — os recibos guardam nome completo, endereço e itens comprados de cada cliente, dado pessoal o bastante para justificar uma segunda camada de controle, separada do IAM, com trilha de auditoria própria no CloudTrail (todo `kms:Decrypt` vira um evento, algo que SSE-S3 nunca ofereceu).

O desenvolvedor responsável cria a CMK pelo console. No passo de "Key usage permissions", para não travar o próprio trabalho enquanto ainda termina de configurar a role certa do backend do checkout, ele copia um trecho de key policy encontrado num fórum e cola direto no editor JSON — só que troca, sem perceber, `"Principal": {"AWS": "arn:aws:iam::<account-id>:root"}` (a forma certa de dizer "confio em qualquer identidade autorizada por IAM nesta conta") por `"Principal": "*"` (que não significa "esta conta" — significa *qualquer principal, de qualquer conta AWS do planeta*). É a mesma confusão do capítulo 03, só que invertida: lá era `Principal: "*"` na trust policy de uma IAM Role; aqui é `Principal: "*"` na key policy de uma CMK. E desta vez não sobra a rede de segurança automática do capítulo 05 — um bucket S3 tem Block Public Access para recusar isso de cara; uma key policy do KMS não tem nada parecido. O `put-key-policy` simplesmente retorna sucesso.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCheckoutBackendKeyUsage",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["kms:Decrypt", "kms:GenerateDataKey*"],
      "Resource": "*"
    }
  ]
}
```

Para completar, ele também deixa em pé a statement padrão que a AWS anexa automaticamente a toda CMK criada sem uma `policy` customizada — `"Enable IAM User Permissions"`, `Principal` igual ao root da conta, `Action: "kms:*"` — por achar que ela é inofensiva, já que "só dá acesso pra quem já tem permissão de IAM". Só que é exatamente essa delegação que faz da key policy um espelho da IAM em vez de um controle independente: qualquer política IAM futura ampla demais (o mesmo tipo de erro do capítulo 01, antes da correção) já bastaria sozinha para decifrar os recibos — sem precisar nem do `Principal: "*"` acima.

Sem tempo (nem lembrança) de marcar "Automatically rotate this KMS key every year", a rotação também fica desligada. A mesma chave, criada num único momento, seguiria em uso indefinidamente — sem a troca periódica do material criptográfico por trás dela que reduz o impacto de um eventual comprometimento.

## 🚨 O Problema

1. **Key policy com `Principal: "*"` = chave publicamente acessível.** Diferente de um bucket S3 (capítulo 05), o AWS KMS **não tem nenhum equivalente ao Block Public Access** — nenhuma trava de conta ou de recurso impede uma key policy assim de ir para produção; a API aceita a chamada normalmente. Mapeado pelo AWS Security Hub como [KMS.5 — *KMS keys should not be publicly accessible*](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-5), severidade **Critical**. A única rede de segurança contínua possível seria o IAM Access Analyzer (capítulo 03) — ele suporta KMS key policy como tipo de recurso monitorado e geraria um *finding* de acesso externo assim que essa policy fosse aplicada — mas só se estivesse ligado, e neste cenário não estava.
2. **Key policy delegando tudo para IAM anula a vantagem central de ter uma CMK.** Manter a statement padrão `"Enable IAM User Permissions"` (root da conta, `kms:*`) faz da key policy um mero espelho de qualquer decisão já tomada em IAM — deixa de ser um segundo portão independente. É o oposto do que o AWS Well-Architected Framework — Security Pillar (SEC08-BP01, *Implement secure key management*) descreve como gerenciamento seguro de chave: controle de acesso definido *junto* com storage e rotação, não terceirizado inteiramente para outro sistema. Também é a lacuna que deixa uma conta exposta ao padrão descrito em [KMS.1](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-1) / [KMS.2](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-2) (*IAM policies should not allow decryption actions on all KMS keys*): sem uma key policy que realmente restrinja, a única linha de defesa restante é uma IAM policy bem escrita — e a Insecurity Inc. já provou, no capítulo 01, que isso sozinho não é confiável.
3. **Rotação de chave desabilitada.** Mapeado no CIS AWS Foundations Benchmark v3.0.0, controle 3.6 (*Ensure rotation for customer-managed symmetric encryption KMS keys is enabled* — mesmo número no v5.0.0; controle 3.8 no v1.4.0; controle 2.8 no v1.2.0), e no AWS Security Hub como [KMS.4](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-4).

## ✅ A Correção

Este capítulo implementa os dois conceitos do título — Encryption e Key Policy — como camadas complementares, mantendo o mesmo princípio de defesa em profundidade do capítulo 05:

1. **CMK simétrica** (`aws_kms_key.customer_receipts`) dedicada ao bucket de recibos, com **rotação automática habilitada** (`enable_key_rotation = true`, resolve o ponto 3 do Problema) e `deletion_window_in_days` parametrizado (padrão 7, o mínimo permitido pela AWS — ver `variables.tf` para a nota de custo).
2. **Key policy escrita do zero, sem a statement padrão de delegação para IAM e sem `Principal: "*"`** — resolve os pontos 1 e 2 do Problema ao mesmo tempo. Em vez disso, dois principais são nomeados explicitamente:
   - `AllowKeyAdministration`: escopado à identidade que aplica o Terraform, com as ações administrativas da chave (criar, descrever, habilitar/desabilitar, agendar/cancelar deleção, tags) — mas **sem** `kms:Encrypt`/`kms:Decrypt`/`kms:GenerateDataKey*`. Administrar a chave não deveria implicar poder ler os dados que ela protege.
   - `AllowCheckoutBackendKeyUsageViaS3Only`: escopado ao `var.checkout_backend_principal_arn` (por padrão, a própria identidade do Terraform, para manter o capítulo self-contained — no cenário real seria a role específica do backend, capítulo 01), com só as ações de uso (`kms:Encrypt`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`, `kms:DescribeKey`).
3. **Condição `kms:ViaService` restringindo o uso ao S3** — mesmo o principal autorizado acima não consegue chamar `kms:Decrypt`/`kms:Encrypt` diretamente; só através de uma operação do S3 na região configurada. Camada extra de defesa em profundidade, no mesmo espírito do `DenyInsecureTransport` do capítulo 05: mesmo uma credencial legítima comprometida não vira uma ferramenta genérica de descriptografia.
4. **Alias amigável** (`alias/insecurity-inc-customer-receipts`) — facilita rastrear a chave nos eventos do CloudTrail sem decorar o Key ID.
5. **Bucket S3 de exemplo** (mesmo cenário do capítulo 05, reconstruído aqui porque cada capítulo deste repositório é autocontido) com Bucket Owner Enforced e Public Access Block como linha de base, agora cifrado com **SSE-KMS** apontando para a CMK acima, e `bucket_key_enabled = true` — um S3 Bucket Key reduz em até ~99% o número de chamadas do S3 ao KMS por objeto, relevante numa conta sem free tier.

O resultado: mesmo sem um Block Public Access para KMS, a defesa aqui vem inteiramente de uma key policy bem escrita — o que reforça por que revisar key policy manualmente (e manter o Access Analyzer do capítulo 03 ligado) importa tanto quanto qualquer trava automática da AWS. A seção "Como testar" abaixo prova, na prática, tanto a robustez da correção quanto a ausência real dessa trava.

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes (exceto pelo sufixo aleatório do bucket, que você escolhe manualmente nos caminhos 2 e 3), então dá para misturar.

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
SUFFIX=$(openssl rand -hex 4)
BUCKET_NAME="insecurity-inc-customer-receipts-${SUFFIX}"

# 1. Key policy explícita -- sem "Enable IAM User Permissions", sem
#    Principal "*". CALLER_ARN faz o papel dos dois principais (admin e
#    backend do checkout) só para manter o laboratório self-contained.
cat > /tmp/kms-key-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowKeyAdministration",
      "Effect": "Allow",
      "Principal": {"AWS": "${CALLER_ARN}"},
      "Action": [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
        "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowCheckoutBackendKeyUsageViaS3Only",
      "Effect": "Allow",
      "Principal": {"AWS": "${CALLER_ARN}"},
      "Action": [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {"kms:ViaService": "s3.${REGION}.amazonaws.com"}
      }
    }
  ]
}
EOF

# 2. Criar a CMK e habilitar rotação automática
KEY_ID=$(aws kms create-key \
  --description "CMK do capítulo 06 (insecurity-inc) -- cifra o bucket de recibos de cliente via SSE-KMS." \
  --policy file:///tmp/kms-key-policy.json \
  --tags TagKey=project,TagValue=insecurity-inc TagKey=env,TagValue=lab TagKey=chapter,TagValue=06 \
  --query KeyMetadata.KeyId --output text)

aws kms enable-key-rotation --key-id "$KEY_ID"

aws kms create-alias \
  --alias-name alias/insecurity-inc-customer-receipts \
  --target-key-id "$KEY_ID"

# 3. Criar o bucket (assume us-east-1, a região default deste capítulo; se a
#    sua região não for us-east-1, adicione
#    --create-bucket-configuration LocationConstraint=$REGION)
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"

aws s3api put-bucket-tagging --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=project,Value=insecurity-inc},{Key=env,Value=lab},{Key=chapter,Value=06}]'

aws s3api put-bucket-ownership-controls \
  --bucket "$BUCKET_NAME" \
  --ownership-controls Rules=[{ObjectOwnership=BucketOwnerEnforced}]

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 4. Ativar SSE-KMS com a CMK acima + S3 Bucket Key
KEY_ARN=$(aws kms describe-key --key-id "$KEY_ID" --query KeyMetadata.Arn --output text)

aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration "{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\",\"KMSMasterKeyID\":\"${KEY_ARN}\"},\"BucketKeyEnabled\":true}]}"
```

### 🖥️ Opção 3 — Console (GUI)

1. **Criar a CMK:** console **KMS** → **Customer managed keys** → **Create key** → tipo **Symmetric**, uso **Encrypt and decrypt** → alias `insecurity-inc-customer-receipts` → tags `project=insecurity-inc`, `env=lab`, `chapter=06` → em **Key administrators**, selecione só a sua própria identidade → em **Key usage permissions**, selecione também só a sua própria identidade (representando o backend do checkout) → **Finish**.
2. **Editar a key policy para adicionar a condição `kms:ViaService`:** chave criada → aba **Key policy** → **Edit** → alterne para o editor **Policy view**, remova a statement `"Enable IAM User Permissions"` gerada automaticamente e cole o JSON completo da Opção 2 (com o ARN real da sua identidade) → **Save changes**.
3. **Habilitar rotação:** aba **Key rotation** → marque **Automatically rotate this KMS key every year** → **Save**.
4. **Criar o bucket:** console **S3** → **Create bucket** → nome `insecurity-inc-customer-receipts-<algo-único-seu>` → em **Object Ownership**, **ACLs disabled (recommended)** → mantenha as quatro opções de **Block Public Access** marcadas → em **Default encryption**, selecione **AWS Key Management Service key (SSE-KMS)** → **Choose from your AWS KMS keys** → selecione `insecurity-inc-customer-receipts` → marque **Bucket Key** → **Create bucket**.
5. **Adicionar tags do bucket:** aba **Properties** → seção **Tags** → **Edit** → `project=insecurity-inc`, `env=lab`, `chapter=06` → **Save changes**.

## 🧾 Como testar

O objetivo é provar, na prática, quatro coisas: o fluxo legítimo de cifra/decifra via S3 continua funcionando; a condição `kms:ViaService` bloqueia até a identidade autorizada de usar a chave fora do S3; uma segunda identidade com uma IAM policy ampla (reproduzindo o erro do capítulo 01) continua sendo negada pela key policy, mesmo tendo permissão de IAM; e — o ponto central deste capítulo — a AWS não tem nenhuma trava que impeça, de fato, uma key policy pública, ao contrário do S3.

Requer o utilitário `jq` para ler as credenciais temporárias do `sts assume-role`.

```bash
KEY_ID=$(terraform output -raw kms_key_id)
BUCKET_NAME=$(terraform output -raw bucket_name)
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)

# 1. Fluxo legítimo: cifrar e decifrar via S3 continua funcionando
echo "recibo de teste" > /tmp/receipt.txt
aws s3 cp /tmp/receipt.txt "s3://${BUCKET_NAME}/receipt-teste.txt"

aws s3api head-object --bucket "$BUCKET_NAME" --key receipt-teste.txt \
  --query '{SSE:ServerSideEncryption,KeyId:SSEKMSKeyId}'
# Esperado: SSE = "aws:kms", KeyId = o ARN da CMK deste capítulo

aws s3 cp "s3://${BUCKET_NAME}/receipt-teste.txt" -   # imprime "recibo de teste"

# 2. kms:ViaService: até a identidade autorizada é negada fora do S3
#    (--plaintext precisa vir em base64 -- comportamento padrão do AWS CLI
#    v2 para parâmetros binários)
PLAINTEXT_B64=$(echo -n "teste direto, sem passar pelo S3" | base64)
aws kms encrypt --key-id "$KEY_ID" --plaintext "$PLAINTEXT_B64" \
  --output text --query CiphertextBlob
# Esperado: AccessDeniedException -- a condition exige que a chamada venha
# de s3.<region>.amazonaws.com; uma chamada direta ao KMS não satisfaz essa
# condição, mesmo vindo da mesma identidade autorizada para usar a chave.

# 3. Rotação automática está de fato habilitada
aws kms get-key-rotation-status --key-id "$KEY_ID"
# Esperado: "KeyRotationEnabled": true

# 4. Key policy como segundo portão independente: uma role nova, com uma
#    IAM policy AMPLA de kms:Decrypt (reproduzindo o erro do capítulo 01),
#    mas SEM nenhuma menção na key policy, continua sendo negada. A policy
#    também precisa incluir s3:GetObject -- ler um objeto SSE-KMS exige as
#    DUAS permissões ao mesmo tempo (s3:GetObject via IAM + kms:Decrypt via
#    key policy); sem s3:GetObject, o S3 já nega a chamada sozinho (um
#    "Forbidden" genérico, do HeadObject interno do "aws s3 cp") e o teste
#    não isola mais a key policy como a variável sendo provada.
cat > /tmp/kms-lab-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::${ACCOUNT_ID}:root"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name insecurity-inc-kms-lab-unauthorized \
  --assume-role-policy-document file:///tmp/kms-lab-trust.json \
  --description "TEMPORÁRIA -- reproduz o erro do capítulo 01 (IAM policy ampla demais) só para provar que a key policy deste capítulo nega mesmo assim."

cat > /tmp/kms-lab-broad-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:GenerateDataKey*"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name insecurity-inc-kms-lab-unauthorized \
  --policy-name broad-kms-decrypt \
  --policy-document file:///tmp/kms-lab-broad-policy.json

sleep 10   # propagação do IAM antes de assumir a role

ASSUMED=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/insecurity-inc-kms-lab-unauthorized" \
  --role-session-name kms-lab-test-1)
export AWS_ACCESS_KEY_ID=$(echo "$ASSUMED" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUMED" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$ASSUMED" | jq -r .Credentials.SessionToken)

aws s3 cp "s3://${BUCKET_NAME}/receipt-teste.txt" -
# Esperado: negado -- mesmo com s3:GetObject E kms:Decrypt liberados por IAM
# (Resource "*" do lado do KMS), a key policy não tem a statement "Enable
# IAM User Permissions" nem nomeia essa role -- permissão de IAM sozinha não
# basta. Prova concreta do ponto 2 do Problema. Verificado com AWS CLI v2
# (2.34.62): o "aws s3 cp" reporta um "AccessDenied" descritivo, citando
# kms:Decrypt como a ação negada -- não um "Forbidden" genérico.

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# 5. O ponto central: reproduzir o Principal "*" do Cenário na key policy
#    REAL deste capítulo, e provar que a AWS aceita sem reclamar -- ao
#    contrário do S3, não existe Block Public Access para KMS.
aws kms get-key-policy --key-id "$KEY_ID" --policy-name default \
  --query Policy --output text > /tmp/kms-correct-policy.json   # guarda a policy correta

# Confira que o backup não ficou vazio antes de continuar -- se "$KEY_ID"
# não estiver definido nesta sessão de shell (por exemplo, se você reabriu
# o terminal entre os passos), o comando acima falha silenciosamente e
# grava um arquivo vazio, o que quebra o "put-key-policy" de reversão no
# passo 7 com MalformedPolicyDocumentException.
test -s /tmp/kms-correct-policy.json && echo "Backup OK" || echo "BACKUP VAZIO -- não continue sem corrigir"

cat > /tmp/kms-public-policy-attempt.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowKeyAdministration",
      "Effect": "Allow",
      "Principal": {"AWS": "${CALLER_ARN}"},
      "Action": [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*",
        "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:Disable*",
        "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
        "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ReproduzErroDoCenario",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["kms:Decrypt", "kms:GenerateDataKey*"],
      "Resource": "*"
    }
  ]
}
EOF

aws kms put-key-policy --key-id "$KEY_ID" --policy-name default \
  --policy file:///tmp/kms-public-policy-attempt.json
echo "Sem erro -- a AWS aceitou uma key policy com Principal público normalmente."

# 6. Confirmar o estrago: a MESMA role sem permissão nenhuma na key policy
#    original agora consegue decifrar, só porque Principal "*" cobre
#    literalmente qualquer principal autenticado.
ASSUMED=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/insecurity-inc-kms-lab-unauthorized" \
  --role-session-name kms-lab-test-2)
export AWS_ACCESS_KEY_ID=$(echo "$ASSUMED" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUMED" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$ASSUMED" | jq -r .Credentials.SessionToken)

aws s3 cp "s3://${BUCKET_NAME}/receipt-teste.txt" -
# Esperado: funciona -- "recibo de teste" impresso. A statement
# "ReproduzErroDoCenario" (Principal "*") já basta SOZINHA para isso: numa
# key policy do KMS, uma statement que nomeia um principal (por ARN
# específico ou por "*") concede a permissão diretamente, sem exigir
# nenhuma IAM policy correspondente -- a IAM policy "broad-kms-decrypt" que
# essa role carrega desde o passo 4 não é mais o que está autorizando isto
# (dá pra confirmar removendo-a e repetindo o comando: continua funcionando).
#
# A exposição é real, não teórica, mesmo para uma conta EXTERNA: o AWS exige
# que o principal externo tenha também uma IAM policy correspondente na
# PRÓPRIA conta dele -- mas como é ele mesmo quem concede essa permissão a
# si mesmo, sem precisar de nenhuma cooperação da sua conta, isso não é uma
# barreira de verdade. Qualquer conta AWS do planeta que descubra o ARN
# desta chave consegue decifrar em poucos segundos.

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# 7. Reverter IMEDIATAMENTE para a key policy correta e confirmar que a
#    role voltou a ser negada
aws kms put-key-policy --key-id "$KEY_ID" --policy-name default \
  --policy file:///tmp/kms-correct-policy.json

ASSUMED=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/insecurity-inc-kms-lab-unauthorized" \
  --role-session-name kms-lab-test-3)
export AWS_ACCESS_KEY_ID=$(echo "$ASSUMED" | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUMED" | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "$ASSUMED" | jq -r .Credentials.SessionToken)

aws s3 cp "s3://${BUCKET_NAME}/receipt-teste.txt" -
# Esperado: AccessDenied de novo.

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

Depois do teste, remova os recursos temporários e os arquivos locais:

```bash
aws iam delete-role-policy --role-name insecurity-inc-kms-lab-unauthorized --policy-name broad-kms-decrypt
aws iam delete-role --role-name insecurity-inc-kms-lab-unauthorized
aws s3 rm "s3://${BUCKET_NAME}/receipt-teste.txt"
rm -f /tmp/receipt.txt /tmp/kms-lab-trust.json /tmp/kms-lab-broad-policy.json \
      /tmp/kms-correct-policy.json /tmp/kms-public-policy-attempt.json
```

### 🖥️ Repetindo os testes 3 e 5 — Console (GUI)

- **Rotação:** chave → aba **Key rotation** → confirme **Automatic key rotation** como "Enabled".
- **Key policy pública:** chave → aba **Key policy** → **Edit** → cole o segundo JSON do passo 5 acima → **Save changes** — repare que a AWS salva normalmente, sem nenhum aviso equivalente ao do Block Public Access do S3. Reverta em seguida para o JSON original salvo no passo 5.

## 🧹 Como destruir

### 🏗️ Terraform

```bash
terraform destroy
```

> `terraform destroy` chama `ScheduleKeyDeletion` na CMK, não uma deleção imediata: a chave entra em estado **Pending deletion** pelo número de dias definido em `key_deletion_window_days` (padrão 7, o mínimo da AWS) e só é apagada de fato ao final dessa janela — continuando cobrada (~US$1/mês, pro-rata) até lá, mesmo já "destruída" do ponto de vista do Terraform. Não há como acelerar isso pagando mais: 7 dias é o piso técnico da AWS. O bucket é criado com `force_destroy = true` pelo mesmo motivo do capítulo 05 — garantir que o destroy funcione mesmo com o objeto de teste ainda no bucket; **nunca** use isso em produção.

### ⌨️ AWS CLI

```bash
aws s3 rm "s3://${BUCKET_NAME}" --recursive
aws s3api delete-bucket --bucket "$BUCKET_NAME"

aws kms delete-alias --alias-name alias/insecurity-inc-customer-receipts
aws kms schedule-key-deletion --key-id "$KEY_ID" --pending-window-in-days 7
```

### 🖥️ Console (GUI)

1. **S3** → selecione o bucket → **Empty** → digite o nome do bucket para confirmar → **Empty**. Com o bucket vazio, selecione-o novamente → **Delete** → confirme → **Delete bucket**.
2. **KMS** → **Customer managed keys** → selecione `insecurity-inc-customer-receipts` → **Key actions** → **Schedule key deletion** → defina a janela mínima (7 dias) → confirme.

## 📚 Referências

- [SEC08-BP01 — Implement secure key management](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_protect_data_rest_key_mgmt.html) — AWS Well-Architected Framework, Security Pillar; base da separação entre administração e uso da chave implementada neste capítulo.
- CIS AWS Foundations Benchmark v3.0.0, controle 3.6 — *Ensure rotation for customer-managed symmetric encryption KMS keys is enabled* (mesmo número no v5.0.0; controle 3.8 no v1.4.0; controle 2.8 no v1.2.0) — mapeado no AWS Security Hub como [KMS.4](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-4).
- AWS Security Hub — [KMS.5 — KMS keys should not be publicly accessible](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-5) — o controle que descreve exatamente o erro do Cenário deste capítulo.
- AWS Security Hub — [KMS.1](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-1) / [KMS.2](https://docs.aws.amazon.com/securityhub/latest/userguide/kms-controls.html#kms-2) — políticas IAM não deveriam permitir `kms:Decrypt`/`kms:ReEncryptFrom` em todas as chaves; a última linha de defesa quando a key policy delega tudo para IAM (ponto 2 do Problema).
- [Key policies in AWS KMS](https://docs.aws.amazon.com/kms/latest/developerguide/key-policies.html) — referência oficial de key policy, incluindo a seção sobre quando *não* delegar para IAM.
- [Default key policy](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html) — documenta a statement `"Enable IAM User Permissions"` que este capítulo deliberadamente não usa.
- [How to restrict KMS key usage — kms:ViaService](https://docs.aws.amazon.com/kms/latest/developerguide/conditions-aws.html) — referência oficial da condição usada para restringir o uso da CMK exclusivamente a chamadas feitas através do S3.
- [Reducing the cost of SSE-KMS with Amazon S3 Bucket Keys](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html) — referência oficial de `bucket_key_enabled`, usado neste capítulo para reduzir o número de chamadas ao KMS.
- [IAM Access Analyzer supported resource types](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-resources.html) — confirma que chave KMS é um dos tipos de recurso monitorados pelo Access Analyzer do capítulo 03, citado no ponto 1 do Problema.
- [AWS Key Management Service Pricing](https://aws.amazon.com/kms/pricing/) — ~US$1/mês por CMK (pro-rata) + ~US$0.03/10.000 requisições simétricas além da cota gratuita mensal — base da nota de custo 🟡 deste capítulo.
