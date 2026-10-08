# 15 — 🛡️ Organizations + RCP

![Capa do capítulo 15 — Organizations + RCP](../imagens/cover-S01E15.jpg)

**Arco:** Governança (Org)  
**Conceito:** Guardrail do lado do recurso  
**Well-Architected:** [SEC03-BP05](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_define_guardrails.html)\*  
**Custo:** 🟢  
**Depende de:** capítulo(s) 05, 06 (conceito), 14 (Organization e conta-membro)

> \* RCP ainda não é citado nominalmente no AWS Well-Architected Framework (feature lançada no final de 2024) — SEC03-BP05 é a prática mais próxima por analogia, já que descreve o mesmo conceito de guardrail organizacional aplicado a SCP.

## 🎬 Cenário

A Insecurity Inc. dormiu tranquila depois do capítulo 14: a conta nova está numa OU, com uma SCP que impede qualquer administrador de lá de desligar o CloudTrail ou sair da organização. "A organização agora manda nas contas."

Na segunda-feira, um engenheiro da conta nova precisa compartilhar um relatório com um fornecedor. Cria um bucket, sobe o arquivo e, para "facilitar", escreve uma bucket policy com `"Principal": "*"` — exatamente o erro que o capítulo 05 corrigiu na conta original. A conta nova não tem Block Public Access no nível da conta (ninguém aplicou o capítulo 05 lá), então a AWS aceita a policy sem reclamar. O arquivo agora está disponível para qualquer pessoa na internet, sem credencial nenhuma.

A SCP do capítulo 14 não percebe nada. E não é falha dela: o fornecedor, o crawler anônimo e o atacante não pertencem à organização. Uma SCP só limita identidades *da* organização. Quem está do lado de fora entra pela porta que a bucket policy abriu, e nenhuma SCP chega até essa porta.

## 🚨 O Problema

1. **A resource policy é a porta de entrada de quem está fora.** Bucket policy, key policy, secret policy e queue policy decidem quem *de fora da conta* pode acessar um recurso. IAM e SCP só alcançam as identidades da própria conta e da própria organização. Para um chamador externo (outra conta AWS, ou um pedido anônimo), a única coisa entre ele e o dado é a resource policy que alguém da conta escreveu. Um erro ali é exposição direta.
2. **Cada correção do arco "Dados" foi feita recurso a recurso, conta a conta.** O `DenyInsecureTransport` e o Public Access Block do capítulo 05 valem para *um* bucket. A key policy restrita do capítulo 06 vale para *uma* chave. Nada disso é herdado por um bucket novo, numa conta nova, criado por alguém que nunca leu esses capítulos.
3. **SEC03-BP05 pede guardrails que operem fora da conta**, e a AWS completou esse modelo em novembro de 2024: a SCP passou a ter um par do lado do recurso, a Resource Control Policy (RCP). A RCP é avaliada junto da resource policy de todo recurso de uma conta-membro e vale para qualquer chamador, de dentro ou de fora da organização, inclusive anônimo e inclusive o usuário root de outra conta.
4. **Confirmado ao vivo nesta organização, antes deste capítulo:**
   - `list-roots` mostrava só `SERVICE_CONTROL_POLICY` habilitado no Root; RCP não estava ligada.
   - A conta-membro `868878695337` não tinha Block Public Access no nível da conta (`NoSuchPublicAccessBlockConfiguration`).
   - Um bucket de teste com `"Principal": "*"` na bucket policy devolveu o objeto para um `curl` anônimo, com HTTP 200, tanto por HTTPS quanto por HTTP puro.
   - Uma chamada assinada da própria conta, sem TLS (`--endpoint-url http://...`), também passou.

## ✅ A Correção

1. **Habilita `RESOURCE_CONTROL_POLICY` no Root da Organization.** É pré-requisito manual (CLI/Console), não Terraform, pela mesma razão do capítulo 14: o único lugar para isso no provider seria o resource `aws_organizations_organization`, e esse resource chama `DeleteOrganization` no destroy (ver a Nota de incidente do [capítulo 14](../14-organizations-scp/README.md)). Ao habilitar, a AWS anexa automaticamente a `RCPFullAWSAccess` no Root, em toda OU e em toda conta. Ela deixa tudo passar pela avaliação de RCP e não pode ser desanexada.
2. **Cria uma RCP (`insecurity-inc-data-perimeter`) com 2 guardrails**, baseados nos exemplos oficiais da AWS (`aws-samples/data-perimeter-policy-examples` e a página de sintaxe de RCP):
   - **`EnforceOrgIdentities` — perímetro de identidade.** Nega S3, KMS, Secrets Manager, SQS e o subconjunto de STS usado para entrar numa conta (`AssumeRole`, `GetSessionToken`, `GetFederationToken`, ...) quando `aws:PrincipalOrgID` não é o ID desta organização.
     - O operador é `StringNotEqualsIfExists`. Um pedido anônimo não tem `aws:PrincipalOrgID` no contexto, e o `IfExists` faz essa ausência também cair no Deny. É esse detalhe que fecha o bucket "acidentalmente público" do Cenário.
     - A exceção `BoolIfExists aws:PrincipalIsAWSService = false` deixa passar serviços AWS que agem com o próprio service principal (ex.: CloudTrail entregando log num bucket, como no capítulo 11), que não têm `PrincipalOrgID`.
   - **`EnforceSecureTransport` — TLS obrigatório.** Nega os mesmos serviços quando `aws:SecureTransport` é `false`. É o `DenyInsecureTransport` do capítulo 05 promovido de "um bucket" para "todo bucket, chave, secret e fila da conta", inclusive os que ainda não existem.
3. **Anexa a RCP direto na conta-membro**, não no Root nem numa OU. É a ordem que a própria AWS recomenda para RCP ("attach RCPs to individual test accounts, moving them up to OUs lower in the hierarchy, and then working your way up"). O alvo é a variável `rcp_target_id`, que aceita conta, OU ou Root. Subir na hierarquia é trocar um valor, não reescrever a policy. De quebra, o capítulo não precisa importar a conta (`aws_organizations_account`), então o `destroy` não tem nenhum caminho até `RemoveAccountFromOrganization`.

As regras de sintaxe de RCP moldam o documento:

- Só `Effect: Deny`; `Allow` é exclusivo da `RCPFullAWSAccess`.
- `Principal` só pode ser `"*"`. Quem é barrado se decide no `Condition`.
- `Action: "*"` sozinho não é aceito: cada serviço precisa aparecer explicitamente (`s3:*`, `kms:*`, ...).
- Sem `NotPrincipal` nem `NotAction`.

### SCP × RCP

| | SCP (capítulo 14) | RCP (este capítulo) |
| --- | --- | --- |
| Limita | O que as identidades **da** organização podem fazer | O que **qualquer** identidade pode fazer nos recursos da organização |
| Alcança chamador de fora da organização / anônimo | Não | Sim |
| Lado da avaliação | Junto da identity policy | Junto da resource policy |
| Serviços | Todos | Lista de serviços suportados ([docs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html#rcp-supported-services)), que já inclui S3, KMS, STS, SQS, Secrets Manager, DynamoDB, ECR, CloudWatch Logs e dezenas de outros |
| Management account | Não afetada | Não afetada (recursos dela) |
| Fora do alcance | Service-linked roles | Service-linked roles, AWS managed keys do KMS, `kms:RetireGrant` |

As duas se completam. A SCP impede que alguém de dentro desligue os controles; a RCP impede que alguém de fora entre por uma resource policy mal escrita. Nenhuma das duas *concede* nada: o acesso efetivo continua sendo a interseção com as policies de IAM e de recurso.

## 💵 Nota de custo

🟢 — RCPs não têm custo próprio. O teste cria um bucket S3 com um objeto de 50 bytes por alguns minutos (centavos de centavo) e apaga tudo ao final. Nenhuma CMK do KMS é criada: o KMS do capítulo 06 entra no escopo da policy, mas não é testado ao vivo, para não gerar a cobrança mínima da chave (ver Dívidas em aberto).

## 🧪 Como aplicar

Três caminhos equivalentes. **Dois pré-requisitos comuns aos três, sem equivalente Terraform**, rodados com credencial da **management account** (exceto o `accept-handshake`):

```bash
# 1. A conta-membro precisa estar dentro da Organization. O "Como destruir"
#    do capítulo 14 tira a conta da organização -- se você veio de lá,
#    convide de novo.
MEMBER_ACCOUNT_ID="868878695337"
aws organizations invite-account-to-organization \
  --target Id="$MEMBER_ACCOUNT_ID",Type=ACCOUNT
# Do lado da conta convidada, usando credenciais DELA:
aws organizations accept-handshake --handshake-id <handshake-id-recebido>

# 2. RESOURCE_CONTROL_POLICY precisa estar habilitado no Root.
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
[ -n "$ROOT_ID" ] && [ "$ROOT_ID" != None ] || echo "ROOT_ID VAZIA -- não continue sem corrigir (confira o login AWS na management account)"
aws organizations enable-policy-type --root-id "$ROOT_ID" --policy-type RESOURCE_CONTROL_POLICY
# O status passa por PENDING_ENABLE e vira ENABLED em poucos segundos:
aws organizations list-roots --query 'Roots[0].PolicyTypes' --output table
```

> Troque `868878695337` pelo ID da sua conta-membro. RCP exige uma organização com *all features* habilitado; uma organização só com *consolidated billing* não tem esse tipo de policy.

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform plan    # esperado: 2 to add (a policy e o attachment), nada mais
terraform apply
```

Para anexar em outro alvo (uma OU ou o Root, depois de testado na conta), passe `-var 'rcp_target_id=ou-xxxx-xxxxxxxx'` ou `-var 'rcp_target_id=r-xxxx'`.

### ⌨️ Opção 2 — AWS CLI

Assume os pré-requisitos já feitos (acima), com `$MEMBER_ACCOUNT_ID` exportado nesta sessão de shell.

```bash
ORG_ID=$(aws organizations describe-organization --query 'Organization.Id' --output text)
[ -n "$ORG_ID" ] && [ "$ORG_ID" != None ] || echo "ORG_ID VAZIA -- não continue sem corrigir (confira o login AWS na management account)"

cat > /tmp/insecurity-inc-data-perimeter.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnforceOrgIdentities",
      "Effect": "Deny",
      "Principal": "*",
      "Action": [
        "s3:*", "kms:*", "secretsmanager:*", "sqs:*",
        "sts:AssumeRole", "sts:DecodeAuthorizationMessage", "sts:GetAccessKeyInfo",
        "sts:GetFederationToken", "sts:GetServiceBearerToken", "sts:GetSessionToken",
        "sts:SetContext"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEqualsIfExists": { "aws:PrincipalOrgID": "${ORG_ID}" },
        "BoolIfExists": { "aws:PrincipalIsAWSService": "false" }
      }
    },
    {
      "Sid": "EnforceSecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": ["s3:*", "kms:*", "secretsmanager:*", "sqs:*", "sts:*"],
      "Resource": "*",
      "Condition": { "BoolIfExists": { "aws:SecureTransport": "false" } }
    }
  ]
}
EOF

POLICY_ID=$(aws organizations create-policy --name insecurity-inc-data-perimeter \
  --type RESOURCE_CONTROL_POLICY \
  --description "Perímetro de dados do lado do recurso: sem chamador de fora da organização, sem requisição sem TLS." \
  --content file:///tmp/insecurity-inc-data-perimeter.json \
  --tags Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=15 \
  --query 'Policy.PolicySummary.Id' --output text)
[ -n "$POLICY_ID" ] && [ "$POLICY_ID" != None ] || echo "POLICY_ID VAZIA -- não continue sem corrigir"

aws organizations attach-policy --policy-id "$POLICY_ID" --target-id "$MEMBER_ACCOUNT_ID"
```

O heredoc usa `<<EOF` (sem aspas) de propósito, para o shell substituir `${ORG_ID}`. Confira o arquivo gerado antes do `create-policy`: com `ORG_ID` vazio, a condição compararia com uma string vazia e negaria acesso a todo mundo, inclusive à própria organização.

### 🖥️ Console (GUI)

1. **AWS Organizations** → **Policies** → **Resource control policies** → **Enable resource control policies**.
2. **AWS Organizations** → **Settings** (ou o painel inicial) → anote o **Organization ID** (`o-...`).
3. **Policies** → **Resource control policies** → **Create policy** → nome `insecurity-inc-data-perimeter` → cole o mesmo JSON do bloco CLI acima, trocando `${ORG_ID}` pelo ID anotado no passo 2 → adicione as tags `project=insecurity-inc`, `env=lab`, `chapter=15`.
4. Abra a policy criada → **Targets** → **Attach** → selecione a **conta-membro** (não o Root, não a management account).

## 🧾 Como testar

A RCP vale para os recursos da conta-membro, então o bucket de teste precisa ser criado **lá dentro**. O teste reproduz o erro do Cenário de propósito: um bucket com bucket policy pública. É um recurso temporário fora do Terraform, apagado ao final, mesmo padrão dos capítulos 13 e 14.

Requer uma credencial de administrador **na conta-membro** (não na management account). Rode o bloco 2 duas vezes, antes e depois do `apply`, para ver a diferença.

```bash
# Bloco 1 -- bucket "acidentalmente público" na conta-membro.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
[ -n "$ACCOUNT_ID" ] && [ "$ACCOUNT_ID" != None ] || echo "ACCOUNT_ID VAZIA -- não continue sem corrigir (confira o login AWS da conta-membro)"
BUCKET="insecurity-inc-15-rcp-test-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "$BUCKET" --region us-east-1
aws s3api put-bucket-tagging --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=project,Value=insecurity-inc},{Key=env,Value=lab},{Key=chapter,Value=15}]'
echo "recibo do cliente 42 -- nao deveria estar publico" > /tmp/receipt.txt
aws s3api put-object --bucket "$BUCKET" --key receipt.txt --body /tmp/receipt.txt

# O erro do capítulo 05, repetido: desliga o Block Public Access do bucket
# e escreve uma bucket policy com Principal "*".
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"OopsPublicRead\", \"Effect\": \"Allow\", \"Principal\": \"*\",
    \"Action\": \"s3:GetObject\", \"Resource\": \"arn:aws:s3:::${BUCKET}/*\"
  }]
}"
```

Se o `put-bucket-policy` falhar com `AccessDenied` mencionando Block Public Access, a conta-membro tem BPA ligado no nível da conta. Isso é bom, mas impede este teste específico. Pule direto para os dois últimos comandos do bloco 2 (o teste de TLS), que não dependem de bucket público.

```bash
# Bloco 2 -- rode antes e depois do apply.
[ -n "$BUCKET" ] && [ "$BUCKET" != "insecurity-inc-15-rcp-test-" ] || echo "BUCKET VAZIA -- não continue sem corrigir (rode o bloco 1 nesta mesma sessão de shell)"

# a) Anônimo (de fora da organização, sem credencial nenhuma), HTTPS e HTTP:
curl -s -o /dev/null -w 'anonimo HTTPS: HTTP %{http_code}\n' "https://${BUCKET}.s3.amazonaws.com/receipt.txt"
curl -s -o /dev/null -w 'anonimo HTTP:  HTTP %{http_code}\n' "http://${BUCKET}.s3.amazonaws.com/receipt.txt"

# b) A própria conta-membro, sem TLS (endpoint http://):
aws s3api get-object --bucket "$BUCKET" --key receipt.txt \
  --endpoint-url http://s3.us-east-1.amazonaws.com /dev/null

# c) Contraprova -- a própria conta-membro, com TLS (deve continuar funcionando):
aws s3api head-object --bucket "$BUCKET" --key receipt.txt --query ContentLength --output text
```

```bash
# Bloco 3 -- limpeza.
aws s3api delete-object --bucket "$BUCKET" --key receipt.txt
aws s3api delete-bucket --bucket "$BUCKET" --region us-east-1
rm -f /tmp/receipt.txt
```

Resultado real, nesta conta. **Antes do `apply`** (só a `RCPFullAWSAccess` anexada), tudo aberto:

```text
anonimo HTTPS: HTTP 200
anonimo HTTP:  HTTP 200
(chamada sem TLS: sucesso -- nesta rodada testada com head-object no endpoint http://, ContentLength 50)
50
```

**Depois do `apply`:**

```text
anonimo HTTPS: HTTP 403
anonimo HTTP:  HTTP 403

An error occurred (AccessDenied) when calling the GetObject operation:
User: arn:aws:iam::868878695337:user/ayeka-testes is not authorized to perform:
s3:GetObject on resource: "arn:aws:s3:::insecurity-inc-15-rcp-test-868878695337/receipt.txt"
with an explicit deny in a resource control policy:
arn:aws:organizations::230650392331:policy/o-u56soehvgp/resource_control_policy/p-026h9kp9gn

50
```

Como ler esse resultado:

- **O bucket continua "público" do ponto de vista dele mesmo.** A bucket policy com `Principal: "*"` e o BPA desligado não mudaram entre as duas rodadas. A única diferença foi a RCP anexada à conta. O 403 anônimo não cita a RCP pelo nome, porque a AWS não detalha o motivo da negação para quem não se autenticou, mas a comparação antes/depois isola a causa.
- **O pedido sem TLS cita a RCP explicitamente** (`explicit deny in a resource control policy` + ARN da policy). É a prova direta de que o bloqueio vem da organização, não de algo na conta: `ayeka-testes` tem `AdministratorAccess` e é dono do bucket.
- **A contraprova (`50`, o tamanho do objeto) mostra que o acesso legítimo não foi afetado.** A mesma identidade, com TLS, continua lendo o objeto normalmente.

Um teste extra feito nesta sessão, fora do bloco acima porque exige credencial das duas contas: acrescentando à bucket policy de teste um `Allow` para `arn:aws:iam::230650392331:root` (a management account, que está **dentro** da organização), o usuário `ayeka` da management account leu o objeto por HTTPS normalmente: acesso entre contas da organização continua passando pelo perímetro. A mesma leitura **sem TLS** foi negada com `explicit deny in a resource control policy`. A RCP não se aplica a recursos *da* management account, mas se aplica a *chamadas feitas por ela* contra recursos de uma conta-membro.

## 📋 Dívidas em aberto

- **Perímetro testado só com chamador anônimo, não com uma identidade de outra conta AWS fora da organização.** Esta organização não tem uma terceira conta para isso. O anônimo exercita o ramo "a chave `aws:PrincipalOrgID` não existe" (o `IfExists`); uma identidade externa assinada exercitaria o ramo "a chave existe e é diferente". É a mesma statement e a mesma condição, mas esse segundo caminho não foi provado ponta a ponta.
- **Só S3 testado ao vivo.** KMS, Secrets Manager, SQS e STS estão no escopo da policy, mas testar KMS exigiria uma CMK (~US$1/mês prorrateado, com janela mínima de 7 dias ainda cobrada na deleção — ver capítulo 06) e Secrets Manager cobra por secret (capítulo 08).
- **Sem proteção contra confused deputy.** A exceção `aws:PrincipalIsAWSService` deixa passar *qualquer* serviço AWS agindo com service principal, inclusive em nome de uma conta de fora da organização. O exemplo oficial da AWS fecha isso com uma terceira statement baseada em `aws:SourceOrgID`/`aws:SourceAccount`. Ficou de fora para o capítulo continuar pequeno e testável.
- **Sem mecanismo de exceção.** Um parceiro externo legítimo (o fornecedor do Cenário) também é bloqueado. Um perímetro de produção precisa de uma lista de contas confiáveis (`aws:PrincipalAccount`) ou de uma tag de exceção por recurso (`aws:ResourceTag/dp:exclude:identity`), como no exemplo da AWS, além de um processo para aprovar essas exceções.
- **Sem perímetro de rede.** O terceiro pilar de um data perimeter na AWS ("acesso só a partir de redes esperadas", via `aws:SourceIp`/`aws:SourceVpc`) não é tratado aqui.
- **Anexada à conta, não à OU nem ao Root.** É o primeiro degrau do rollout progressivo recomendado pela AWS. O próximo passo, numa organização real, seria anexar a uma OU de teste e depois ao Root, revisando os `AccessDenied` no CloudTrail entre cada degrau.
- **RCP não substitui o Block Public Access.** O bucket de teste continua com uma bucket policy pública que só não funciona porque a RCP barra a requisição. O correto continua sendo BPA ligado no nível da conta (capítulo 05). A RCP é a rede de proteção para quando essa lição não chegou a uma conta, não um motivo para dispensá-la.
- **A conta-membro continua na organização depois do "Como destruir"**, ao contrário do capítulo 14. Este capítulo não importa a conta, então não tem o que tirar dela. Ser membro da organização não custa nada. Para devolver a conta ao estado standalone: `aws organizations remove-account-from-organization --account-id 868878695337` (management account).
- **`RESOURCE_CONTROL_POLICY` continua habilitado no Root depois do "Como destruir"**, de propósito, pelo mesmo motivo do `SERVICE_CONTROL_POLICY` no capítulo 14: é configuração da organização inteira, não do ciclo de vida deste capítulo. Com só a `RCPFullAWSAccess` anexada, o efeito prático é nenhum.

## 🧹 Como destruir

Antes de qualquer caminho, rode o **bloco 3 do Como testar** (limpeza do bucket de teste) com a credencial da conta-membro, se ainda não rodou. Ele não é gerenciado pelo Terraform.

### 🏗️ Terraform

```bash
terraform destroy
```

O destroy desanexa a RCP da conta e apaga a policy. A conta-membro, a `RCPFullAWSAccess` e o tipo de policy habilitado no Root não são tocados (ver Dívidas em aberto).

### ⌨️ AWS CLI

```bash
MEMBER_ACCOUNT_ID="868878695337"
POLICY_ID=$(aws organizations list-policies --filter RESOURCE_CONTROL_POLICY --query "Policies[?Name=='insecurity-inc-data-perimeter'].Id" --output text)
[ -n "$POLICY_ID" ] && [ "$POLICY_ID" != None ] || echo "POLICY_ID VAZIA -- não continue sem corrigir (confira o login AWS na management account)"

aws organizations detach-policy --policy-id "$POLICY_ID" --target-id "$MEMBER_ACCOUNT_ID"
aws organizations delete-policy --policy-id "$POLICY_ID"
```

### 🖥️ Console (GUI)

1. **AWS Organizations** → **Policies** → **Resource control policies** → `insecurity-inc-data-perimeter` → **Targets** → selecione a conta-membro → **Detach**.
2. Ainda na policy → **Actions** → **Delete policy**.

Depois do destroy (de qualquer um dos três caminhos), confira que não sobrou nada:

```bash
aws organizations list-policies --filter RESOURCE_CONTROL_POLICY --query "Policies[].Name" --output text
# Esperado: só RCPFullAWSAccess

aws organizations list-policies-for-target --target-id 868878695337 --filter RESOURCE_CONTROL_POLICY --query "Policies[].Name" --output text
# Esperado: só RCPFullAWSAccess

aws s3api head-bucket --bucket insecurity-inc-15-rcp-test-868878695337   # com credencial da conta-membro
# Esperado: erro 404 (bucket de teste apagado)
```

## 📚 Referências

- [SEC03-BP05 — Define permission guardrails for your organization](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_define_guardrails.html) — AWS Well-Architected Framework, Security Pillar; prática mais próxima, por analogia (ver nota no topo).
- [Resource control policies (RCPs)](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html) — AWS Organizations User Guide; lista de serviços suportados, management account fora do alcance, service-linked roles e AWS managed keys excluídas, recomendação de testar numa conta antes do Root.
- [RCP syntax](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps_syntax.html) — só `Deny`, `Principal: "*"`, `Action: "*"` proibido, sem `NotPrincipal`/`NotAction`; base do `EnforceSecureTransport`.
- [Understanding SCPs and RCPs](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_authorization_policies.html) — quando usar cada uma.
- [aws-samples/data-perimeter-policy-examples — `identity_perimeter_rcp.json`](https://github.com/aws-samples/data-perimeter-policy-examples/blob/main/resource_control_policies/identity_perimeter_rcp.json) — base do `EnforceOrgIdentities` e das exceções/statements deixadas de fora (ver Dívidas em aberto).
- [aws-samples/resource-control-policy-examples](https://github.com/aws-samples/resource-control-policy-examples) — catálogo oficial de exemplos de RCP.
- [Building a data perimeter on AWS](https://docs.aws.amazon.com/whitepapers/latest/building-a-data-perimeter-on-aws/building-a-data-perimeter-on-aws.html) — whitepaper; os três perímetros (identidade, recurso, rede) dos quais este capítulo implementa o primeiro.
- [AWS global condition context keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html) — `aws:PrincipalOrgID`, `aws:PrincipalIsAWSService`, `aws:SecureTransport`.
- Terraform AWS provider: [`aws_organizations_organization` (data source)](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/organizations_organization), [`aws_organizations_policy`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy), [`aws_organizations_policy_attachment`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_policy_attachment).
- Capítulo [05](../05-s3-security/README.md) — o `DenyInsecureTransport` e o Block Public Access que esta RCP generaliza para a conta inteira.
- Capítulo [06](../06-kms/README.md) — a key policy restrita que `kms:*` no perímetro complementa.
- Capítulo [14](../14-organizations-scp/README.md) — a SCP, guardrail do lado da identidade, e a Nota de incidente que explica por que a Organization é `data`, não `resource`.
