# 02 — 🏷️ ABAC

**Arco:** Identidade
**Conceito:** Policy dinâmica por tags
**Custo:** 🟢
**Depende de:** capítulo(s) 01

## 🎬 Cenário

O RBAC do capítulo 01 funcionou bem para a primeira analista. Mas a Insecurity Inc. cresceu: agora tem gente de **marketing** e de **engenharia**, cada time com seu próprio bucket de relatórios. Seguindo à risca o padrão que "funcionou da última vez", o fundador repete a receita do capítulo 01 para cada time novo: um bucket, uma customer-managed policy escopada a esse bucket, um grupo.

No terceiro time, ao copiar e colar a policy do time de marketing para criar a do time de engenharia, alguém esquece de trocar o ARN do recurso. O JSON que vai para o grupo `insecurity-inc-engineering-analysts` fica assim:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadWriteReportsObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::insecurity-inc-reports-marketing-lab-<account-id>/*"
    }
  ]
}
```

O nome do grupo diz "engineering", a policy aponta para o bucket de "marketing". O erro só seria percebido quando alguém do time de engenharia reclamasse de não conseguir acessar nada — ou, pior, quando alguém do time de marketing notasse que gente de fora está lendo seus relatórios.

## 🚨 O Problema

1. **Policy sprawl.** RBAC estático (capítulo 01) exige uma policy nova, escrita à mão, para cada combinação de time × recurso. Com *N* times, são *N* buckets, *N* policies e *N* grupos para manter e auditar — o esforço cresce linearmente (e o risco de erro, junto).
2. **Erro humano por copy-paste vira uma falha de segurança real.** O JSON acima não é hipotético: é o tipo de engano que acontece quando "criar acesso para um time novo" significa "duplicar o JSON do time anterior e editar os campos certos". Um ARN esquecido concede acesso cruzado entre times — exatamente o tipo de vazamento de escopo que o least privilege deveria evitar.
3. **Auditoria não escala.** Para responder "quem pode acessar os relatórios de marketing?" é preciso abrir e ler cada policy de cada grupo, uma a uma — não existe um único lugar ou uma única regra para consultar.

O AWS Well-Architected Framework — Security Pillar (SEC03-BP02, *Grant least privilege access*) aponta justamente essa limitação de escalar permissões via policies estáticas conforme o número de times/recursos cresce, e recomenda **attribute-based access control (ABAC)** como alternativa: em vez de uma policy por recurso, uma única policy cujo escopo é resolvido dinamicamente a partir de atributos (tags) da própria identidade que faz a chamada.

## ✅ A Correção

Este capítulo reestrutura o acesso aos relatórios como ABAC, reaproveitando o conceito do capítulo 01 (S3 + IAM Group), mas trocando "uma policy por time" por "uma policy para todos os times":

1. **Um único bucket compartilhado** (`insecurity-inc-team-reports-lab-<account-id>`), particionado por prefixo/pasta — uma pasta por time (`marketing/`, `engineering/`) em vez de um bucket por time.
2. **Uma única customer-managed policy** (`insecurity-inc-abac-team-reports-policy`) que **não menciona nenhum time por nome**. Em vez disso, usa variáveis de policy do IAM para resolver o escopo em tempo de avaliação:
   - `s3:ListBucket` no bucket, condicionado a `s3:prefix` bater com `${aws:PrincipalTag/access-project}/*` — a identidade só consegue listar a própria pasta.
   - `s3:GetObject`/`s3:PutObject`, com `Resource` igual a `<bucket-arn>/${aws:PrincipalTag/access-project}/*` — a identidade só consegue ler/gravar dentro da própria pasta.
   - Uma condição `Null` em ambas as statements exige que a tag `access-project` exista no principal — sem ela, a AWS nega o acesso em vez de resolver a variável de forma imprevisível. É a mitigação recomendada pelo próprio [tutorial de ABAC da AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_attribute-based-access-control.html).
3. **Um único IAM Group** (`insecurity-inc-abac-analysts`) recebendo essa policy — de novo, nunca anexada direto a um usuário (CIS AWS Foundations Benchmark v3.0.0, controle 1.15).
4. **Um usuário IAM por time de exemplo** (`insecurity-inc-marketing-analyst`, `insecurity-inc-engineering-analyst`), todos no mesmo grupo, com a **mesma** policy — o que diferencia o acesso de cada um é só o valor da tag `access-project` (`marketing` ou `engineering`).

Onboarding de um time novo deixa de significar "escrever uma policy nova": significa criar a pasta no bucket e taguear a identidade com `access-project=<time>`. Nenhuma policy é tocada — e por isso o erro de copy-paste do cenário acima deixa de ser possível: não existe um segundo JSON para copiar.

Essa é também a razão pela qual o [CLAUDE.md](../CLAUDE.md#convenções) deste repositório insiste em tagging consistente desde o capítulo 00/01: ABAC não funciona sem tags corretas e presentes em toda identidade e recurso.

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar.

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

O nome do bucket é `${team_reports_bucket_name}-<account-id>` (prefixo definido em `variables.tf`, sufixado com o Account ID para garantir unicidade global). Os times de exemplo (`marketing`, `engineering`) também estão em `variables.tf`, na variável `teams`.

### ⌨️ Opção 2 — AWS CLI

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="insecurity-inc-team-reports-lab-${ACCOUNT_ID}"

# 1. Criar o bucket compartilhado
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region us-east-1
# em região != us-east-1, adicione:
# --create-bucket-configuration LocationConstraint=<região>

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=project,Value=insecurity-inc},{Key=env,Value=lab},{Key=chapter,Value=02}]'

# 2. Criar uma "pasta" (marcador vazio) por time
aws s3api put-object --bucket "$BUCKET_NAME" --key "marketing/"
aws s3api put-object --bucket "$BUCKET_NAME" --key "engineering/"

# 3. Criar a policy ABAC — uma só, sem nenhum time no nome ou no JSON
cat > /tmp/abac-team-reports-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListOwnPrefixOnly",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}",
      "Condition": {
        "StringLike": {"s3:prefix": ["\${aws:PrincipalTag/access-project}/*"]},
        "Null": {"aws:PrincipalTag/access-project": "false"}
      }
    },
    {
      "Sid": "ReadWriteOwnPrefixOnly",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/\${aws:PrincipalTag/access-project}/*",
      "Condition": {
        "Null": {"aws:PrincipalTag/access-project": "false"}
      }
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name insecurity-inc-abac-team-reports-policy \
  --policy-document file:///tmp/abac-team-reports-policy.json \
  --description "Acesso dinamico ao bucket compartilhado via tag access-project (ABAC)."
# guarde o Arn retornado
POLICY_ARN=<Arn retornado acima>

# 4. Criar o grupo e anexar a policy (uma única vez, para todos os times)
aws iam create-group --group-name insecurity-inc-abac-analysts

aws iam attach-group-policy \
  --group-name insecurity-inc-abac-analysts \
  --policy-arn "$POLICY_ARN"

# 5. Criar um usuário por time, cada um com a tag access-project correspondente
aws iam create-user \
  --user-name insecurity-inc-marketing-analyst \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=02 Key=access-project,Value=marketing

aws iam create-user \
  --user-name insecurity-inc-engineering-analyst \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=02 Key=access-project,Value=engineering

aws iam add-user-to-group --user-name insecurity-inc-marketing-analyst --group-name insecurity-inc-abac-analysts
aws iam add-user-to-group --user-name insecurity-inc-engineering-analyst --group-name insecurity-inc-abac-analysts
```

> Note o `\$` antes de `{aws:PrincipalTag...}` no heredoc: é só para o shell não tentar expandir a variável antes de gravar o arquivo. No Console (Opção 3) ou em qualquer editor comum, escreva `${aws:PrincipalTag/access-project}` normalmente, sem barra invertida.

### 🖥️ Opção 3 — Console (GUI)

1. **Criar o bucket:** console **S3** → **Create bucket** → nome `insecurity-inc-team-reports-lab-<account-id>` → região desejada → deixe **Block all public access** marcado (padrão) → em *Tags*, adicione `project=insecurity-inc`, `env=lab`, `chapter=02` → **Create bucket**.
2. **Criar as pastas:** dentro do bucket → **Create folder** → `marketing` → **Create folder**; repita para `engineering`.
3. **Criar a policy:** console **IAM** → **Policies** → **Create policy** → aba **JSON** → cole o JSON da Opção 2 (com o nome real do bucket, sem as barras invertidas antes de `${...}`) → **Next** → nome `insecurity-inc-abac-team-reports-policy`, descrição "Acesso dinâmico ao bucket compartilhado via tag access-project (ABAC)." → **Create policy**.
4. **Criar o grupo:** **IAM** → **User groups** → **Create group** → nome `insecurity-inc-abac-analysts` → em **Attach permissions policies**, marque `insecurity-inc-abac-team-reports-policy` → **Create group**.
5. **Criar os usuários:** **IAM** → **Users** → **Create user** → nome `insecurity-inc-marketing-analyst` → **não** marque acesso ao Console → **Next** → em **Add user to group**, selecione `insecurity-inc-abac-analysts` → **Create user**. Depois, abra o usuário criado → aba **Tags** → **Add new tag** → chave `access-project`, valor `marketing`. Repita tudo para `insecurity-inc-engineering-analyst` com valor `engineering`.

## 🧾 Como testar

Diferente do capítulo 01 (uma identidade só), aqui o objetivo é comparar **duas** identidades com a mesma policy e ver o escopo divergir por causa da tag. A forma mais direta é via access key temporária + AWS CLI (login de console também funcionaria, mas comparar dois usuários fica mais rápido no terminal). Assim como no capítulo 01, o Terraform **não** gera credenciais — crie-as manualmente, teste, e remova em seguida.

```bash
# 1. Criar uma access key temporária para cada analista de teste
aws iam create-access-key --user-name insecurity-inc-marketing-analyst > /tmp/marketing-key.json
aws iam create-access-key --user-name insecurity-inc-engineering-analyst > /tmp/engineering-key.json

# 2. Configurar um profile local para cada uma
aws configure set aws_access_key_id "$(jq -r .AccessKey.AccessKeyId /tmp/marketing-key.json)" --profile marketing-analyst
aws configure set aws_secret_access_key "$(jq -r .AccessKey.SecretAccessKey /tmp/marketing-key.json)" --profile marketing-analyst

aws configure set aws_access_key_id "$(jq -r .AccessKey.AccessKeyId /tmp/engineering-key.json)" --profile engineering-analyst
aws configure set aws_secret_access_key "$(jq -r .AccessKey.SecretAccessKey /tmp/engineering-key.json)" --profile engineering-analyst

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="insecurity-inc-team-reports-lab-${ACCOUNT_ID}"

# 3. A analista de marketing só enxerga a própria pasta
aws s3 ls "s3://${BUCKET_NAME}/marketing/" --profile marketing-analyst        # funciona
aws s3 ls "s3://${BUCKET_NAME}/engineering/" --profile marketing-analyst     # AccessDenied

echo "teste" > /tmp/relatorio.txt
aws s3 cp /tmp/relatorio.txt "s3://${BUCKET_NAME}/marketing/relatorio.txt" --profile marketing-analyst   # funciona
aws s3 cp /tmp/relatorio.txt "s3://${BUCKET_NAME}/engineering/relatorio.txt" --profile marketing-analyst # AccessDenied

# 4. O analista de engenharia vive o espelho: só a própria pasta
aws s3 ls "s3://${BUCKET_NAME}/engineering/" --profile engineering-analyst   # funciona
aws s3 ls "s3://${BUCKET_NAME}/marketing/" --profile engineering-analyst    # AccessDenied
```

A mesma policy, o mesmo grupo — o que muda o resultado é só a tag `access-project` de cada identidade. É essa a demonstração de que "uma regra, N times" funciona.

Depois do teste, revogue as access keys (elas são credenciais de longa duração — não deixe nenhuma viva além do necessário; ciclo de vida de credenciais é assunto do capítulo 04):

```bash
aws iam delete-access-key --user-name insecurity-inc-marketing-analyst \
  --access-key-id "$(jq -r .AccessKey.AccessKeyId /tmp/marketing-key.json)"
aws iam delete-access-key --user-name insecurity-inc-engineering-analyst \
  --access-key-id "$(jq -r .AccessKey.AccessKeyId /tmp/engineering-key.json)"
rm -f /tmp/marketing-key.json /tmp/engineering-key.json /tmp/relatorio.txt
```

## 🧹 Como destruir

Destrua pelo mesmo caminho que usou para aplicar (ou combine, já que os nomes de recurso são os mesmos nos três). Se você criou access keys de teste (seção "Como testar") e ainda não as revogou, remova-as antes — o Terraform não gerencia essas credenciais e não vai tocar nelas sozinho.

> **Erro comum:** `terraform destroy` falha com `DeleteConflict: Cannot delete entity, must delete access keys first` se alguma access key de teste ainda existir. Resolva listando e removendo as chaves de cada analista antes de destruir de novo:
>
> ```bash
> for TEAM in marketing engineering; do
>   USER="insecurity-inc-${TEAM}-analyst"
>   for KEY_ID in $(aws iam list-access-keys --user-name "$USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
>     aws iam delete-access-key --user-name "$USER" --access-key-id "$KEY_ID"
>   done
> done
> ```

### 🏗️ Terraform

```bash
terraform destroy
```

### ⌨️ AWS CLI

```bash
for TEAM in marketing engineering; do
  aws iam remove-user-from-group \
    --user-name "insecurity-inc-${TEAM}-analyst" \
    --group-name insecurity-inc-abac-analysts
  aws iam delete-user --user-name "insecurity-inc-${TEAM}-analyst"
done

POLICY_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='insecurity-inc-abac-team-reports-policy'].Arn" \
  --output text)

aws iam detach-group-policy \
  --group-name insecurity-inc-abac-analysts \
  --policy-arn "$POLICY_ARN"

aws iam delete-group --group-name insecurity-inc-abac-analysts

aws iam delete-policy --policy-arn "$POLICY_ARN"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="insecurity-inc-team-reports-lab-${ACCOUNT_ID}"

aws s3 rm "s3://$BUCKET_NAME" --recursive   # remove objetos e marcadores de pasta
aws s3api delete-bucket --bucket "$BUCKET_NAME"
```

### 🖥️ Console (GUI)

1. **IAM** → **Users** → selecione `insecurity-inc-marketing-analyst` e `insecurity-inc-engineering-analyst` → **Delete** (um de cada vez).
2. **IAM** → **User groups** → selecione `insecurity-inc-abac-analysts` → **Delete** (se pedir para remover policies anexadas antes, desanexe `insecurity-inc-abac-team-reports-policy` primeiro).
3. **IAM** → **Policies** → filtre por *Customer managed* → selecione `insecurity-inc-abac-team-reports-policy` → **Delete**.
4. **S3** → selecione o bucket `insecurity-inc-team-reports-lab-<account-id>` → **Empty** (esvaziar objetos, incluindo os marcadores de pasta) → confirme → **Delete** → confirme digitando o nome do bucket.

## 📚 Referências

- [SEC03-BP02 — Grant least privilege access](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_least_privileges.html) — AWS Well-Architected Framework, Security Pillar; discute ABAC como estratégia para escalar least privilege conforme o número de times/recursos cresce.
- [Attribute-based access control (ABAC) for AWS](https://docs.aws.amazon.com/IAM/latest/UserGuide/introduction_attribute-based-access-control.html) — visão geral oficial do IAM sobre ABAC, incluindo quando preferi-lo a RBAC.
- [IAM tutorial: Define permissions to access AWS resources based on tags](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_attribute-based-access-control.html) — tutorial oficial que originou o padrão `aws:PrincipalTag` + condição `Null` usado neste capítulo.
- [IAM JSON policy elements: Variables and tags](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_variables.html) — referência da sintaxe `${aws:PrincipalTag/chave}` usada nas statements de `Resource` e `Condition`.
- [Amazon S3: Example — restrict access to a prefix (home directory pattern)](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_s3_rw-home-dir.html) — origem do uso de `s3:prefix` com `StringLike` para limitar `ListBucket` a uma pasta.
- CIS AWS Foundations Benchmark v3.0.0, controle 1.15 — *Ensure IAM Users Receive Permissions Only Through Groups* (a estrutura de grupo do capítulo 01 continua valendo aqui).
