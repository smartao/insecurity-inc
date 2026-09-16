# 04 — 🔐 MFA Enforcement

![Capa do capítulo 04 — MFA Enforcement](../imagens/cover-S01E04.jpg)

**Arco:** Identidade  
**Conceito:** Condição de política exigindo MFA  
**Well-Architected:** [SEC02-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_enforce_mechanisms.html)  
**Custo:** 🟢  

## 🎬 Cenário

O RBAC do capítulo 01 resolveu *o que* o analista de plantão pode fazer. Mas nunca resolveu *como* essa identidade prova que é quem diz ser: quando o analista finalmente precisou de acesso ao Console (não só a scripts via CLI), o fundador criou a senha pelo caminho mais rápido — console **IAM** → **Security credentials** → **Console access** → **Enable** — e mandou usuário e senha por chat. Nenhuma configuração adicional. Username e senha, e mais nada.

Meses depois, esse mesmo analista reaproveitou a senha da AWS num site pessoal — hábito comum e mal visto, mas real. Esse site sofreu um vazamento de dados público, e a combinação usuário/senha vazou junto com milhões de outras (o tipo de dado que circula em serviços de *credential stuffing*). Como a senha era a mesma, e como a conta AWS não tinha absolutamente nenhuma camada de proteção além dela, bastaria um atacante testar essa credencial vazada para entrar — sem alarme, sem etapa extra, sem nada que distinguisse esse login de um login legítimo feito pelo próprio analista.

## 🚨 O Problema

1. **Autenticação de um fator só.** Usuário e senha é uma única prova de identidade — quem a obtiver (phishing, reuso de senha vazada em outro serviço, keylogger, ombro sobre o teclado) entra com exatamente os mesmos privilégios do dono legítimo, sem nenhuma segunda barreira. É exatamente a condição que o CIS AWS Foundations Benchmark v3.0.0, controle 1.10 (*Ensure MFA is enabled for all IAM users that have a console password* — mapeado no Security Hub como [IAM.5](https://docs.aws.amazon.com/securityhub/latest/userguide/iam-controls.html#iam-5)), audita e reporta como não conforme.
2. **Least privilege não é substituto de autenticação forte.** Mesmo que o RBAC do capítulo 01 (ou o ABAC do capítulo 02) esteja perfeito, o que ele faz é *limitar o raio de explosão* de uma identidade comprometida — não impede o comprometimento em si. Seja qual for o escopo de permissões dessa identidade, um atacante de posse da senha herda exatamente esse escopo. As duas mitigações são complementares, não substitutas: least privilege limita o dano de uma conta comprometida; MFA reduz a chance de a conta ser comprometida por uma senha vazada ou adivinhada.
3. **Nenhum backstop na camada de autorização.** Não existia, em nenhuma policy da conta, uma condição que exigisse MFA antes de qualquer ação sensível. Mesmo depois da senha vazar, nada no IAM notaria ou bloquearia a sessão resultante — é exatamente o antipadrão citado pelo AWS Well-Architected Framework, Security Pillar (SEC02-BP01, *Use strong sign-in mechanisms*): "not enforcing a strong sign-in mechanism, e.g. multi-factor authentication (MFA)".

## ✅ A Correção

Este capítulo implementa a mitigação recomendada pelo próprio SEC02-BP01: uma customer-managed policy que nega toda ação da conta, exceto um punhado bem específico de ações IAM, sempre que a sessão não estiver autenticada com MFA — o padrão que a AWS documenta em seu [tutorial oficial de autogestão de credenciais e MFA](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_users-self-manage-mfa-and-creds.html).

1. **Grupo de exemplo** (`insecurity-inc-console-users`) representando qualquer identidade com login de console por senha — deliberadamente um grupo novo, não o `insecurity-inc-oncall-sysops` do capítulo 01: MFA é uma exigência que deveria valer para *toda* identidade humana da conta, não só para um grupo específico (cada capítulo deste repositório é independente e não compartilha state, mas a lição se generaliza — na prática, esta mesma policy de Force MFA seria anexada a todo grupo que tenha usuários com senha de console).
2. **Policy de negócio de exemplo** (`insecurity-inc-console-users-policy`) — o mesmo `ec2:DescribeInstances` de sempre (capítulos 01/02), só para dar ao grupo algo de fato útil para fazer. O ponto deste capítulo não é essa permissão, é a policy abaixo, que decide *quando* ela pode ser exercida.
3. **Policy Force MFA** (`insecurity-inc-force-mfa-policy`), baseada no exemplo oficial da AWS ["AWS: Allows MFA-authenticated IAM users to manage their own credentials on the Security credentials page"](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_aws_my-sec-creds-self-manage.html), reduzida aqui só às ações de senha e MFA (a versão completa da AWS também cobre access keys, certificados de assinatura, chaves SSH e Git credentials do CodeCommit — fora do escopo deste laboratório):
   - Quatro statements `Allow` (`AllowViewAccountInfo`, `AllowManageOwnPasswords`, `AllowManageOwnVirtualMFADevice`, `AllowManageOwnUserMFA`) concedendo exatamente o necessário para o próprio usuário (escopado via `${aws:username}`, nunca um ARN fixo): ver a política de senha da conta, trocar sua própria senha, e criar/listar/habilitar/ressincronizar seu próprio dispositivo MFA virtual — o mínimo para alguém sem MFA ainda conseguir se autoproteger.
   - Uma quinta statement, `DenyAllExceptListedIfNoMFA`, é o coração da policy: `Effect: Deny` combinado com `NotAction` nega **toda** ação da conta que não estiver nessa lista curta — mas só quando a `Condition` `BoolIfExists` sobre `aws:MultiFactorAuthPresent` avaliar `false`. `BoolIfExists` trata a *ausência* da chave como `false`, então isso também nega acesso a quem estiver usando uma credencial de longa duração sem nenhum contexto de MFA (uma access key crua, por exemplo) — não só uma sessão de console sem o segundo fator.
   - `iam:ChangePassword` deliberadamente **não** entra na lista de exceções: a própria AWS recomenda contra isso, porque permitir troca de senha sem MFA já ativo seria uma porta de escape da negação. O efeito prático (e a razão de mencionar isso explicitamente aqui) aparece na seção "Como testar" abaixo.
4. **Usuário de exemplo** (`insecurity-inc-console-analyst`), membro do grupo, sem login de console e sem access key geradas pelo Terraform — mesmo motivo dos capítulos anteriores: credencial de longo prazo não deve viver no state.

Com MFA presente na sessão, a condição da quinta statement deixa de ser satisfeita, a negação não se aplica, e a permissão de negócio (`insecurity-inc-console-users-policy`) volta a valer normalmente. Sem MFA, a identidade consegue exatamente o suficiente para configurar seu próprio segundo fator — e nada além disso.

> Este capítulo não cobre MFA para o **root user** da conta — esse é um controle ainda mais crítico (CIS v3.0.0 controles 1.5/1.6, *Ensure MFA/hardware MFA is enabled for the root user*), mas não é gerenciável via IAM policy (o root não pode ser restringido por policy da mesma forma) nem via Terraform (a AWS não expõe essa configuração por API) — é puramente uma tarefa manual e única de Console, fora do escopo de "o que este repositório aplica via `terraform apply`".

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar. Todos os recursos deste capítulo são IAM puro (grupo, policies, usuário) — sem custo algum, inclusive o dispositivo MFA virtual usado na seção "Como testar".

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

### ⌨️ Opção 2 — AWS CLI

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Criar a policy de negócio de exemplo (describe amplo, mesma limitação
#    da API do EC2 discutida nos capítulos 01/02)
cat > /tmp/console-users-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DescribeEC2Instances",
      "Effect": "Allow",
      "Action": "ec2:DescribeInstances",
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name insecurity-inc-console-users-policy \
  --policy-document file:///tmp/console-users-policy.json \
  --description "Permissao de negocio de exemplo (describe de EC2) para o grupo de usuarios de console -- so exercivel de fato com MFA presente."
BUSINESS_POLICY_ARN=<Arn retornado acima>

# 2. Criar a policy Force MFA
cat > /tmp/force-mfa-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowViewAccountInfo",
      "Effect": "Allow",
      "Action": ["iam:GetAccountPasswordPolicy", "iam:ListVirtualMFADevices"],
      "Resource": "*"
    },
    {
      "Sid": "AllowManageOwnPasswords",
      "Effect": "Allow",
      "Action": ["iam:ChangePassword", "iam:GetUser"],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:user/\${aws:username}"
    },
    {
      "Sid": "AllowManageOwnVirtualMFADevice",
      "Effect": "Allow",
      "Action": ["iam:CreateVirtualMFADevice"],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:mfa/*"
    },
    {
      "Sid": "AllowManageOwnUserMFA",
      "Effect": "Allow",
      "Action": [
        "iam:DeactivateMFADevice",
        "iam:EnableMFADevice",
        "iam:ListMFADevices",
        "iam:ResyncMFADevice"
      ],
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:user/\${aws:username}"
    },
    {
      "Sid": "DenyAllExceptListedIfNoMFA",
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:GetMFADevice",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {"aws:MultiFactorAuthPresent": "false"}
      }
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name insecurity-inc-force-mfa-policy \
  --policy-document file:///tmp/force-mfa-policy.json \
  --description "Nega toda acao da conta, exceto autogestao de senha/MFA, enquanto a sessao nao estiver autenticada com MFA."
FORCE_MFA_POLICY_ARN=<Arn retornado acima>

# 3. Criar o grupo e anexar as duas policies
aws iam create-group --group-name insecurity-inc-console-users

aws iam attach-group-policy --group-name insecurity-inc-console-users --policy-arn "$BUSINESS_POLICY_ARN"
aws iam attach-group-policy --group-name insecurity-inc-console-users --policy-arn "$FORCE_MFA_POLICY_ARN"

# 4. Criar o usuário de exemplo e adicioná-lo ao grupo
aws iam create-user \
  --user-name insecurity-inc-console-analyst \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=04

aws iam add-user-to-group \
  --user-name insecurity-inc-console-analyst \
  --group-name insecurity-inc-console-users
```

> Note o `\$` antes de `{aws:username}` no heredoc: é só para o shell não tentar expandir a variável antes de gravar o arquivo — mesma observação do capítulo 02 para `${aws:PrincipalTag/...}`. No Console (Opção 3), escreva `${aws:username}` normalmente, sem barra invertida.

### 🖥️ Opção 3 — Console (GUI)

1. **Criar a policy de negócio:** console **IAM** → **Policies** → **Create policy** → aba **JSON** → cole o primeiro JSON da Opção 2 → **Next** → nome `insecurity-inc-console-users-policy` → **Create policy**.
2. **Criar a policy Force MFA:** **IAM** → **Policies** → **Create policy** → aba **JSON** → cole o segundo JSON da Opção 2 (com o Account ID real, sem a barra invertida antes de `${aws:username}`) → **Next** → nome `insecurity-inc-force-mfa-policy` → **Create policy**.
3. **Criar o grupo:** **IAM** → **User groups** → **Create group** → nome `insecurity-inc-console-users` → em **Attach permissions policies**, marque as duas policies criadas acima → **Create group**.
4. **Criar o usuário:** **IAM** → **Users** → **Create user** → nome `insecurity-inc-console-analyst` → **não** marque acesso ao Console ainda (isso é feito manualmente na seção "Como testar") → **Next** → em **Add user to group**, selecione `insecurity-inc-console-users` → **Create user**.

## 🧾 Como testar

O objetivo é ver, na prática, a mesma identidade ganhar e perder acesso à permissão de negócio (`ec2:DescribeInstances`) dependendo só da presença de MFA na sessão — sem nunca tocar na policy em si. Assim como nos capítulos anteriores, o Terraform **não** gera credenciais de teste — crie-as manualmente e remova tudo ao final.

> ⚠️ **Erro comum:** ao criar a senha de teste, **não** use `--password-reset-required` (nem marque a opção equivalente no Console). A policy Force MFA propositalmente não inclui `iam:ChangePassword` na lista de exceções (ver seção "A Correção") — se a AWS exigir troca de senha no primeiro login, o usuário fica preso: sem MFA ainda configurado, ele não consegue nem trocar a própria senha para entrar. Configure uma senha definitiva (ou uma temporária sem exigência de troca) para este teste.

```bash
# 1. Criar uma senha de console para o usuário de teste (sem reset obrigatório)
aws iam create-login-profile \
  --user-name insecurity-inc-console-analyst \
  --password 'UmaSenhaForteAqui123!'

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
```

1. **Login sem MFA.** Entre no Console com esse usuário/senha na URL acima. Vá em **EC2 → Instances**: deve dar **Access Denied** — a statement `DenyAllExceptListedIfNoMFA` está negando `ec2:DescribeInstances` porque não há MFA na sessão, mesmo a policy de negócio concedendo essa ação. Tente qualquer outro serviço: também **Access Denied**.
2. **Configurar o primeiro MFA.** No canto superior direito, abra o menu do usuário → **Security credentials** → seção **Multi-factor authentication (MFA)** → **Assign MFA device** → **Authenticator app**. Isso funciona porque `iam:CreateVirtualMFADevice`, `iam:EnableMFADevice` etc. estão na lista de exceções da negação — é exatamente o "mínimo para se autoproteger" que a policy garante mesmo sem MFA. Escaneie o QR code com um app autenticador (Google Authenticator, Authy, etc.) e digite dois códigos consecutivos para confirmar.
3. **Login com MFA.** Saia e entre de novo com o mesmo usuário/senha; desta vez a AWS pede o código do app. Digite-o. Vá em **EC2 → Instances** de novo: agora deve **funcionar** — com `aws:MultiFactorAuthPresent = true`, a condição `BoolIfExists ... "false"` deixa de bater, a negação não se aplica, e a policy de negócio volta a valer. Tente outro serviço (S3, IAM, etc.): continua **Access Denied** — MFA não deu mais permissão nenhuma, só destravou a que já existia.

### ⌨️ Provando a exceção `BoolIfExists` via API (opcional, avançado)

O passo a passo acima prova o efeito no Console. Para provar que a negação também vale para acesso programático — e que "ter MFA" significa "a sessão carrega o contexto de MFA", não "logado como esse usuário" — repita com a CLI:

```bash
# 1. Criar uma access key de longa duração para o mesmo usuário
aws iam create-access-key --user-name insecurity-inc-console-analyst > /tmp/console-analyst-key.json

REGION=$(aws configure get region)
aws configure set aws_access_key_id "$(jq -r .AccessKey.AccessKeyId /tmp/console-analyst-key.json)" --profile console-analyst-raw
aws configure set aws_secret_access_key "$(jq -r .AccessKey.SecretAccessKey /tmp/console-analyst-key.json)" --profile console-analyst-raw
aws configure set region "$REGION" --profile console-analyst-raw

# 2. Com a access key crua (sem nenhum contexto de MFA), describe é negado --
#    BoolIfExists trata a ausência de aws:MultiFactorAuthPresent como "false"
aws ec2 describe-instances --profile console-analyst-raw   # AccessDenied

# 3. Pegar o ARN do dispositivo MFA criado no passo 2 da seção anterior
MFA_ARN=$(aws iam list-mfa-devices --user-name insecurity-inc-console-analyst \
  --query 'MFADevices[0].SerialNumber' --output text)

# 4. Trocar as credenciais de longa duração por uma sessão temporária
#    autenticada com MFA -- gere um código atual no app autenticador e
#    substitua abaixo antes de rodar (o código expira em segundos)
aws sts get-session-token \
  --serial-number "$MFA_ARN" \
  --token-code <codigo-atual-do-app> \
  --profile console-analyst-raw > /tmp/console-analyst-session.json

aws configure set aws_access_key_id "$(jq -r .Credentials.AccessKeyId /tmp/console-analyst-session.json)" --profile console-analyst-mfa
aws configure set aws_secret_access_key "$(jq -r .Credentials.SecretAccessKey /tmp/console-analyst-session.json)" --profile console-analyst-mfa
aws configure set aws_session_token "$(jq -r .Credentials.SessionToken /tmp/console-analyst-session.json)" --profile console-analyst-mfa
aws configure set region "$REGION" --profile console-analyst-mfa

# 5. Com o contexto de MFA presente na sessão temporária, describe funciona
aws ec2 describe-instances --profile console-analyst-mfa   # funciona
```

Depois do teste, desfaça tudo o que foi criado manualmente — nenhum destes recursos é gerenciado pelo Terraform deste capítulo:

```bash
aws iam delete-access-key --user-name insecurity-inc-console-analyst \
  --access-key-id "$(jq -r .AccessKey.AccessKeyId /tmp/console-analyst-key.json)"

MFA_ARN=$(aws iam list-mfa-devices --user-name insecurity-inc-console-analyst \
  --query 'MFADevices[0].SerialNumber' --output text)
aws iam deactivate-mfa-device --user-name insecurity-inc-console-analyst --serial-number "$MFA_ARN"
aws iam delete-virtual-mfa-device --serial-number "$MFA_ARN"

aws iam delete-login-profile --user-name insecurity-inc-console-analyst

rm -f /tmp/console-analyst-key.json /tmp/console-analyst-session.json
```

### 🖥️ Criar senha e MFA de teste — Console (GUI)

1. **IAM** → **Users** → `insecurity-inc-console-analyst` → aba **Security credentials** → **Console access** → **Enable** → defina uma senha e **não** marque "Users must create a new password at next sign-in" → **Apply**.
2. Copie a **Console sign-in URL** da mesma tela e faça login em uma janela anônima/outro navegador. Repita os testes de acesso descritos acima (steps 1–3): sem MFA, `EC2 → Instances` dá Access Denied; depois de configurar o MFA (mesma aba **Security credentials** → **Assign MFA device**) e logar de novo, o describe passa a funcionar.
3. Ao terminar, na mesma aba **Security credentials**: remova o dispositivo MFA (**Remove**) e desabilite o acesso ao Console (**Manage** → **Disable**).

## 🧹 Como destruir

Destrua pelo mesmo caminho que usou para aplicar (ou combine, já que os nomes de recurso são os mesmos nos três). Se você criou senha, access key e/ou dispositivo MFA de teste (seção "Como testar") e ainda não os removeu, remova-os antes — o Terraform não gerencia nenhuma dessas credenciais e não vai tocar nelas sozinho.

> **Erro comum:** `terraform destroy` falha com `DeleteConflict: Cannot delete entity, must detach policies or delete access keys / MFA devices / login profile first` se algum desses três (senha, access key, dispositivo MFA) ainda existir no usuário de teste. Resolva removendo os três (comandos na seção "Como testar", bloco de limpeza) e rode `terraform destroy` de novo.

### 🏗️ Terraform

```bash
terraform destroy
```

### ⌨️ AWS CLI

```bash
aws iam remove-user-from-group \
  --user-name insecurity-inc-console-analyst \
  --group-name insecurity-inc-console-users

aws iam delete-user --user-name insecurity-inc-console-analyst

BUSINESS_POLICY_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='insecurity-inc-console-users-policy'].Arn" --output text)
FORCE_MFA_POLICY_ARN=$(aws iam list-policies --scope Local \
  --query "Policies[?PolicyName=='insecurity-inc-force-mfa-policy'].Arn" --output text)

aws iam detach-group-policy --group-name insecurity-inc-console-users --policy-arn "$BUSINESS_POLICY_ARN"
aws iam detach-group-policy --group-name insecurity-inc-console-users --policy-arn "$FORCE_MFA_POLICY_ARN"

aws iam delete-group --group-name insecurity-inc-console-users

aws iam delete-policy --policy-arn "$BUSINESS_POLICY_ARN"
aws iam delete-policy --policy-arn "$FORCE_MFA_POLICY_ARN"
```

### 🖥️ Console (GUI)

1. **IAM** → **Users** → selecione `insecurity-inc-console-analyst` → **Delete**.
2. **IAM** → **User groups** → selecione `insecurity-inc-console-users` → **Delete** (se pedir para remover policies anexadas antes, desanexe as duas primeiro).
3. **IAM** → **Policies** → filtre por *Customer managed* → selecione `insecurity-inc-console-users-policy` e `insecurity-inc-force-mfa-policy` → **Delete** (uma de cada vez).

## 📚 Referências

- [SEC02-BP01 — Use strong sign-in mechanisms](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_identities_enforce_mechanisms.html) — AWS Well-Architected Framework, Security Pillar; recomenda explicitamente a policy customer-managed de "proíbe tudo, exceto autogestão de credenciais/MFA" implementada neste capítulo.
- CIS AWS Foundations Benchmark v3.0.0, controle 1.10 — *Ensure MFA is enabled for all IAM users that have a console password* (mapeado no Security Hub como [IAM.5](https://docs.aws.amazon.com/securityhub/latest/userguide/iam-controls.html#iam-5); mesmo controle numerado 1.10 no v1.4.0, 1.2 no v1.2.0 e 1.9 no v5.0.0 — [tabela de versões](https://docs.aws.amazon.com/securityhub/latest/userguide/cis-aws-foundations-benchmark.html#cis-version-comparison)).
- [IAM tutorial: Permit users to manage their credentials and MFA settings](https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_users-self-manage-mfa-and-creds.html) — tutorial oficial que este capítulo segue, incluindo o cenário de bloquear todo acesso exceto EC2 (aqui, describe) até o MFA ser configurado.
- [AWS: Allows MFA-authenticated IAM users to manage their own credentials on the Security credentials page](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_aws_my-sec-creds-self-manage.html) — policy oficial "Force_MFA" na qual a `insecurity-inc-force-mfa-policy` deste capítulo é baseada (aqui, reduzida a senha + MFA).
- [Configuring MFA-protected API access](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_configure-api-require.html) — referência oficial sobre `sts:GetSessionToken` e o comportamento de `BoolIfExists` com credenciais de longa duração, usado na seção "Como testar".
- [IAM JSON policy elements: NotAction](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_notaction.html) — referência da semântica `Deny` + `NotAction` usada na statement `DenyAllExceptListedIfNoMFA`.
- [AWS global condition context keys — aws:MultiFactorAuthPresent](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-multifactorauthpresent) — referência oficial da chave de condição usada nesta policy.
- CIS AWS Foundations Benchmark v3.0.0, controle 1.15 — *Ensure IAM Users Receive Permissions Only Through Groups* (a estrutura de grupo dos capítulos 01/02 continua valendo aqui).
