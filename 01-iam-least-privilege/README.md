# 01 — IAM Least Privilege

**Arco:** Identidade
**Conceito:** Policy estática (RBAC)
**Custo:** 🟢

## Cenário

A Insecurity Inc. acabou de contratar a primeira pessoa de fora do time fundador: uma analista de dados que precisa subir e consultar relatórios mensais em um bucket S3 dedicado. Para "resolver rápido", o próprio fundador entra no Console, cria um usuário IAM para ela e anexa diretamente a política gerenciada pela AWS `AdministratorAccess` — sem grupo, sem escopo, sem pensar duas vezes. "Depois a gente ajusta."

Em JSON, o que foi anexado (diretamente ao usuário) é essencialmente isto:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}
```

## O Problema

1. **Excesso de privilégio.** `AdministratorAccess` dá controle total sobre todos os serviços e recursos da conta — infinitamente mais do que ler e gravar objetos em um bucket. Isso é exatamente o antipadrão citado pelo AWS Well-Architected Framework: "defaulting to granting users administrator permissions" (SEC03-BP02 — *Grant least privilege access*).
2. **Policy anexada direto ao usuário.** Sem grupo ou role no meio, cada ajuste de permissão vira uma operação manual por pessoa — não escala e dificulta auditoria. É a violação descrita no CIS AWS Foundations Benchmark v3.0.0, controle 1.15 (*Ensure IAM Users Receive Permissions Only Through Groups*).
3. **Raio de explosão desnecessário.** Se a credencial dessa analista vazar (commit acidental de access key, phishing, laptop comprometido), o atacante herda controle total da conta — não apenas do bucket de relatórios que ela de fato usa.

## A Correção

Este capítulo implementa RBAC via IAM Group + customer-managed policy escopada, seguindo o padrão "conceder apenas o que a função exige":

1. **Bucket S3 de exemplo** (`insecurity-inc-reports-lab-<account-id>`) representando o recurso real que a analista precisa acessar. Já nasce privado (Block Public Access e ACLs desabilitadas são padrão da AWS desde abril/2023) — hardening fino de bucket é assunto do capítulo 05, aqui ele só existe para dar um ARN concreto à policy.
2. **Customer-managed IAM policy** (`insecurity-inc-reports-analyst-policy`), com apenas três ações — `s3:ListBucket` no bucket e `s3:GetObject`/`s3:PutObject` nos objetos — e `Resource` apontando exclusivamente para esse bucket. Nada de `"Action": "*"` nem `"Resource": "*"`.
3. **IAM Group** (`insecurity-inc-report-analysts`) recebendo a policy — nunca um usuário individual (CIS 1.15).
4. **IAM User** de exemplo (`insecurity-inc-report-analyst`) como membro do grupo, sem login de console e sem access key gerada pelo Terraform: credencial de longo prazo não deve viver no state, e o ciclo de vida de credenciais (rotação, MFA) é assunto do capítulo 04. O foco aqui é a estrutura de permissões, não como a analista de fato se autentica.

Com isso, mesmo que a credencial dessa identidade vaze, o atacante só consegue listar/ler/gravar objetos num único bucket — não administrar a conta.

## Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar.

### Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

O nome do bucket é `${reports_bucket_name}-<account-id>` (prefixo definido em `variables.tf`, sufixado com o Account ID para garantir unicidade global do nome).

### Opção 2 — AWS CLI

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="insecurity-inc-reports-lab-${ACCOUNT_ID}"

# 1. Criar o bucket (privado por padrão)
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region us-east-1
# em região != us-east-1, adicione:
# --create-bucket-configuration LocationConstraint=<região>

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=project,Value=insecurity-inc},{Key=env,Value=lab},{Key=chapter,Value=01}]'

# 2. Criar a policy least-privilege, escopada só a este bucket
cat > /tmp/reports-analyst-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListReportsBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}"
    },
    {
      "Sid": "ReadWriteReportsObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name insecurity-inc-reports-analyst-policy \
  --policy-document file:///tmp/reports-analyst-policy.json \
  --description "Acesso de leitura/escrita apenas ao bucket de relatórios (least privilege)."
# guarde o Arn retornado
POLICY_ARN=<Arn retornado acima>

# 3. Criar o grupo e anexar a policy a ele (nunca a um usuário diretamente)
aws iam create-group --group-name insecurity-inc-report-analysts

aws iam attach-group-policy \
  --group-name insecurity-inc-report-analysts \
  --policy-arn "$POLICY_ARN"

# 4. Criar o usuário de exemplo e adicioná-lo ao grupo
aws iam create-user \
  --user-name insecurity-inc-report-analyst \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=01

aws iam add-user-to-group \
  --user-name insecurity-inc-report-analyst \
  --group-name insecurity-inc-report-analysts
```

### Opção 3 — Console (GUI)

1. **Criar o bucket:** console **S3** → **Create bucket** → nome `insecurity-inc-reports-lab-<account-id>` → região desejada → deixe **Block all public access** marcado (padrão) → em *Tags*, adicione `project=insecurity-inc`, `env=lab`, `chapter=01` → **Create bucket**.
2. **Criar a policy:** console **IAM** → **Policies** → **Create policy** → aba **JSON** → cole o JSON da Opção 2 (com o nome real do bucket) → **Next** → nome `insecurity-inc-reports-analyst-policy`, descrição "Acesso de leitura/escrita apenas ao bucket de relatórios (least privilege)." → **Create policy**.
3. **Criar o grupo:** **IAM** → **User groups** → **Create group** → nome `insecurity-inc-report-analysts` → em **Attach permissions policies**, marque `insecurity-inc-reports-analyst-policy` → **Create group**.
4. **Criar o usuário:** **IAM** → **Users** → **Create user** → nome `insecurity-inc-report-analyst` → **não** marque "Provide user access to the AWS Management Console" (login não é necessário para este laboratório) → **Next** → em **Add user to group**, selecione `insecurity-inc-report-analysts` → **Create user**.

## Como testar

Para confirmar na prática que o `insecurity-inc-report-analyst` só consegue mexer no bucket de relatórios (e recebe `AccessDenied` em qualquer outra coisa), é preciso dar a ele acesso de login — o que **não** é feito pelo Terraform deste capítulo de propósito: o recurso `aws_iam_user_login_profile` guardaria a senha no state, geralmente em texto plano. Crie a senha fora do Terraform, teste, e remova em seguida.

### Criar senha de teste — AWS CLI

```bash
# 1. Criar uma senha temporária de console para o usuário
aws iam create-login-profile \
  --user-name insecurity-inc-report-analyst \
  --password 'UmaSenhaForteAqui123!' \
  --password-reset-required
# --password-reset-required força trocar a senha no primeiro login; omita para testar mais rápido

# 2. Descobrir a URL de login da conta
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
```

Logue com esse usuário/senha na URL acima. No console, tente:

- **S3 → bucket `insecurity-inc-reports-lab-<account-id>`**: listar, abrir e fazer upload de um objeto devem funcionar.
- **S3 → qualquer outro bucket**, ou **qualquer outro serviço** (EC2, IAM, etc.): deve dar **Access Denied** — é a policy least-privilege funcionando como esperado.
- **Deletar um objeto** no próprio bucket de relatórios também deve dar **Access Denied**: a policy só concede `GetObject`/`PutObject`, não `DeleteObject`.

Depois do teste, remova a senha:

```bash
aws iam delete-login-profile --user-name insecurity-inc-report-analyst
```

### Criar senha de teste — Console (GUI)

1. **IAM** → **Users** → `insecurity-inc-report-analyst` → aba **Security credentials** → **Console access** → **Enable** → gerar senha automática ou definir uma → **Apply**.
2. Copie a **Console sign-in URL** mostrada na mesma tela (ou monte `https://<account-id>.signin.aws.amazon.com/console`) e faça login em uma janela anônima/outro navegador.
3. Repita os testes de acesso descritos acima (bucket de relatórios funciona, resto dá `AccessDenied`).
4. Ao terminar, volte em **Security credentials** → **Console access** → **Manage** (ou **Disable**) para remover a senha.

## Como destruir

Destrua pelo mesmo caminho que usou para aplicar (ou combine, já que os nomes de recurso são os mesmos nos três). Se você criou uma senha de console para testar (seção "Como testar"), remova-a antes — o Terraform não gerencia essa credencial e não vai tocar nela sozinho.

> **Erro comum:** `terraform destroy` falha com `DeleteConflict: Cannot delete entity, must delete login profile first` se a senha de teste ainda existir. Resolva com `aws iam delete-login-profile --user-name insecurity-inc-report-analyst` e rode `terraform destroy` de novo.

### Terraform

```bash
terraform destroy
```

### AWS CLI

```bash
aws iam remove-user-from-group \
  --user-name insecurity-inc-report-analyst \
  --group-name insecurity-inc-report-analysts

aws iam delete-user --user-name insecurity-inc-report-analyst

POLICY_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='insecurity-inc-reports-analyst-policy'].Arn" \
  --output text)

aws iam detach-group-policy \
  --group-name insecurity-inc-report-analysts \
  --policy-arn "$POLICY_ARN"

aws iam delete-group --group-name insecurity-inc-report-analysts

aws iam delete-policy --policy-arn "$POLICY_ARN"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="insecurity-inc-reports-lab-${ACCOUNT_ID}"

aws s3 rm "s3://$BUCKET_NAME" --recursive   # remove objetos de teste, se houver
aws s3api delete-bucket --bucket "$BUCKET_NAME"
```

### Console (GUI)

1. **IAM** → **Users** → selecione `insecurity-inc-report-analyst` → **Delete**.
2. **IAM** → **User groups** → selecione `insecurity-inc-report-analysts` → **Delete** (se pedir para remover policies anexadas antes, desanexe `insecurity-inc-reports-analyst-policy` primeiro).
3. **IAM** → **Policies** → filtre por *Customer managed* → selecione `insecurity-inc-reports-analyst-policy` → **Delete**.
4. **S3** → selecione o bucket `insecurity-inc-reports-lab-<account-id>` → **Empty** (esvaziar objetos) → confirme → **Delete** → confirme digitando o nome do bucket.

## Referências

- [SEC03-BP02 — Grant least privilege access](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_permissions_least_privileges.html) — AWS Well-Architected Framework, Security Pillar (SEC 3: *How do you manage permissions for people and machines?*).
- CIS AWS Foundations Benchmark v3.0.0, controle 1.15 — *Ensure IAM Users Receive Permissions Only Through Groups*.
- CIS AWS Foundations Benchmark v1.4.0, controle 1.16 — *Ensure IAM policies that grant full "*:*" administrative privileges are not created* ([mapeamento de controles no AWS Security Hub — IAM.1 e IAM.2](https://docs.aws.amazon.com/securityhub/latest/userguide/iam-controls.html)).
- [IAM tutorial: Delegate access using IAM policies with conditions](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_delegate-permissions-with-conditions.html) e [Policies and permissions in IAM](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies.html) — referência oficial para escrever policies escopadas por ação e recurso.
