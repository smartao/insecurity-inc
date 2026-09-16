# 05 — 🪣 S3 Security

![Capa do capítulo 05 — S3 Security](../imagens/cover-S01E05.jpg)

**Arco:** Dados  
**Conceito:** Bucket Policy / Public Access Block  
**Well-Architected:** [SEC08-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_access_control.html)  
**Custo:** 🟢  

## 🎬 Cenário

O checkout do capítulo 01 cresceu: agora, a cada pedido fechado, um recibo em PDF é gerado e precisa chegar ao cliente. Ninguém quer construir login e backend só para isso, então um desenvolvedor resolve do jeito mais rápido — cria um bucket S3 (`insecurity-inc-customer-receipts`) pelo Console, sobe os PDFs, e manda por e-mail um link direto de download para cada cliente. Para o link funcionar sem autenticação nenhuma, dois cliques a mais foram necessários:

1. Na criação do bucket, desmarcar as quatro opções de **Block all public access** — sem isso, o próximo passo nem seria possível.
2. Marcar a ACL do objeto (ou do bucket inteiro) como **public-read**.

O link funciona. O cliente recebe o e-mail, clica, baixa o PDF. Ninguém testou o que acontece se alguém adivinhar (ou enumerar) o nome de *outro* objeto no mesmo bucket — porque o bucket inteiro, não só aquele arquivo, ficou público. Qualquer pessoa na internet que descubra o nome de um objeto consegue baixar o recibo de qualquer outro cliente: nome completo, endereço de entrega, itens comprados, e-mail.

## 🚨 O Problema

1. **Bucket público via ACL, viabilizado por Block Public Access desligado.** A ACL `public-read` sozinha não bastaria — a AWS só a aceita porque o Block Public Access da conta/bucket foi desativado primeiro. É exatamente o antipadrão descrito no AWS Well-Architected Framework, Security Pillar (SEC08-BP04, *Enforce access control*): *"Regularly review the level of access granted in Amazon S3 bucket policies. Avoid using publicly readable or writeable buckets unless absolutely necessary."* Aqui não houve revisão nenhuma — o bucket inteiro (todos os recibos, de todos os clientes, passados e futuros) ficou legível por qualquer um, para resolver a entrega de *um* arquivo a *um* cliente. É o mesmo tipo de causa raiz por trás de vazamentos públicos reais de dados via S3 mal configurado. Mapeado no CIS AWS Foundations Benchmark v3.0.0, controle 2.1.4 (*Ensure that S3 Buckets are configured with 'Block Public Access'* — v5.0.0 mesmo número, v1.4.0 controle 2.1.5), e no AWS Security Hub como [S3.1](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-1) (nível de conta) e [S3.8](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-8) (nível de bucket).
2. **ACL como mecanismo de controle de acesso.** ACL é um mecanismo legado, anterior ao IAM, mais difícil de auditar do que uma bucket policy centralizada — é o que o Security Hub audita como [S3.12](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-12) (*ACLs should not be used to manage user access to S3 general purpose buckets*). A própria AWS recomenda desativar ACLs por completo e concentrar toda concessão de acesso em bucket policy / IAM policy.
3. **Nenhuma exigência de transporte seguro.** Mesmo para quem tem uma permissão IAM legítima de acessar o bucket, nada impedia uma requisição feita por HTTP puro (sem TLS) — os dados trafegariam em texto plano, interceptáveis por qualquer um no caminho da rede (proxy corporativo, Wi-Fi público, etc.). Mapeado no CIS AWS Foundations Benchmark v3.0.0, controle 2.1.1 (*Ensure S3 general purpose buckets require requests to use SSL* — v5.0.0 mesmo número, v1.4.0 controle 2.1.2), Security Hub [S3.5](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-5), e AWS Well-Architected Framework, SEC09-BP02 (*Enforce encryption in transit*).

## ✅ A Correção

Este capítulo implementa exatamente os dois conceitos do título — Bucket Policy e Public Access Block — como camadas independentes e complementares, seguindo o princípio de que nenhuma delas sozinha deveria ser a única linha de defesa:

1. **Bucket S3 de exemplo** (`insecurity-inc-customer-receipts-<sufixo>`) representando o mesmo armazenamento de recibos do cenário acima. O sufixo aleatório existe porque nome de bucket S3 é único globalmente em toda a AWS, não só na conta — sem ele, o `terraform apply` poderia colidir com um bucket de outra conta.
2. **Bucket Owner Enforced** (`aws_s3_bucket_ownership_controls`) desativa ACL por completo neste bucket: toda concessão de acesso passa a depender exclusivamente de bucket policy / IAM policy — resolve o ponto 2 do Problema antes mesmo do Public Access Block entrar em ação, e é o valor padrão para buckets novos desde abril/2023 (aqui declarado explicitamente porque é o oposto direto do "antes" deste capítulo).
3. **Public Access Block no nível do bucket** (`aws_s3_bucket_public_access_block`), com as quatro flags (`block_public_acls`, `ignore_public_acls`, `block_public_policy`, `restrict_public_buckets`) ativas: mesmo que uma bucket policy futura conceda acesso público por engano, a AWS rejeita a operação antes que ela tenha qualquer efeito. É a rede de segurança que deveria ter impedido o "antes" deste capítulo de sequer ser possível.
4. **Criptografia em repouso com SSE-S3** (`aws_s3_bucket_server_side_encryption_configuration`, AES-256) — sem custo adicional, e já o padrão da AWS para buckets novos desde 2023. Declarada aqui de forma explícita para documentar a intenção; o upgrade para SSE-KMS com uma chave gerenciada pelo cliente (chave própria, key policy, auditoria de uso) é o assunto completo do capítulo 06 — fora de escopo aqui.
5. **Bucket policy** (`aws_s3_bucket_policy`) com uma única statement, `DenyInsecureTransport`: nega qualquer ação no bucket ou em seus objetos — de qualquer principal, inclusive do dono da conta — quando a condição `aws:SecureTransport` for `false`. `Effect: Deny` com `Principal: "*"` aqui não abre acesso a ninguém; é o padrão oficial da AWS para este tipo de guarda-rail, resolvendo o ponto 3 do Problema.
6. **Como o cliente final ainda recebe o recibo:** nada acima resolve, sozinho, a necessidade original do cenário — entregar o PDF a alguém que não tem (e não deveria precisar ter) conta AWS. Em vez do link público de antes, quem gera o recibo (o backend do checkout, autenticado com uma credencial IAM legítima) chama `s3:GetObject` através de uma **presigned URL**: uma URL assinada, válida por um tempo curto e escopada a um único objeto. É essa URL — não o link "cru" do bucket — que vai no e-mail do cliente. Presigned URL não é uma concessão de acesso público: é uma requisição já assinada por um principal autorizado, por isso funciona normalmente mesmo com Block Public Access 100% ligado e ACL desativada — ela não aciona nenhuma das quatro flags do Public Access Block, que bloqueiam especificamente concessões via ACL/policy com `Principal: "*"`, não requisições assinadas com expiração. A seção "Como testar" gera e usa uma na prática.

O resultado: mesmo que alguém repita o erro do cenário e tente marcar um objeto como `public-read` ou anexar uma policy pública a este bucket, a tentativa é rejeitada pela própria AWS antes de expor qualquer coisa — e mesmo tráfego autorizado só é aceito sobre TLS. O cliente final continua recebendo o recibo normalmente, só que agora por uma URL temporária e escopada a um único arquivo, não por um bucket inteiro aberto ao mundo. A seção "Como testar" abaixo prova essas quatro coisas na prática.

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
SUFFIX=$(openssl rand -hex 4)
BUCKET_NAME="insecurity-inc-customer-receipts-${SUFFIX}"

# 1. Criar o bucket (comando abaixo assume us-east-1, a região default deste
#    capítulo; se a sua região não for us-east-1, adicione
#    --create-bucket-configuration LocationConstraint=$REGION)
aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION"

aws s3api put-bucket-tagging --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=project,Value=insecurity-inc},{Key=env,Value=lab},{Key=chapter,Value=05}]'

# 2. Desativar ACLs (Bucket Owner Enforced)
aws s3api put-bucket-ownership-controls \
  --bucket "$BUCKET_NAME" \
  --ownership-controls Rules=[{ObjectOwnership=BucketOwnerEnforced}]

# 3. Ativar Block Public Access no nível do bucket
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# 4. Ativar criptografia SSE-S3 por padrão
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 5. Aplicar a bucket policy DenyInsecureTransport
cat > /tmp/customer-receipts-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ],
      "Condition": {
        "Bool": {"aws:SecureTransport": "false"}
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file:///tmp/customer-receipts-policy.json
```

### 🖥️ Opção 3 — Console (GUI)

1. **Criar o bucket:** console **S3** → **Create bucket** → nome `insecurity-inc-customer-receipts-<algo-único-seu>` (nome de bucket é único globalmente) → região desejada → em **Object Ownership**, selecione **ACLs disabled (recommended)** → em **Block Public Access settings for this bucket**, mantenha as quatro opções marcadas (é o padrão) → em **Default encryption**, mantenha **Amazon S3 managed keys (SSE-S3)** (também padrão) → **Create bucket**.
2. **Aplicar a bucket policy:** bucket criado → aba **Permissions** → seção **Bucket policy** → **Edit** → cole o JSON da Opção 2 (com o nome real do seu bucket) → **Save changes**.
3. **Adicionar tags:** aba **Properties** → seção **Tags** → **Edit** → adicione `project=insecurity-inc`, `env=lab`, `chapter=05` → **Save changes**.

## 🧾 Como testar

O objetivo é provar, na prática, as quatro coisas que a correção garante: acesso legítimo do dono continua funcionando normalmente, as duas formas de reabrir o bucket ao público (ACL e bucket policy) — exatamente o que o cenário fez — são ativamente bloqueadas pela própria AWS, e o cliente final ainda consegue baixar o próprio recibo através de uma presigned URL, sem precisar de conta AWS nenhuma.

```bash
BUCKET_NAME=<nome do bucket criado acima>
REGION=$(aws configure get region)

# 0. Sanity check: sem nenhuma concessão pública, acesso anônimo já deveria
#    falhar por padrão (nada de especial deste capítulo ainda, só a postura
#    privada normal de um bucket S3)
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/qualquer-coisa"   # 403

# 1. Acesso legítimo (dono da conta, sobre HTTPS) continua funcionando
echo "recibo de teste" > /tmp/receipt.txt
aws s3 cp /tmp/receipt.txt "s3://${BUCKET_NAME}/receipt-teste.txt"
aws s3 cp "s3://${BUCKET_NAME}/receipt-teste.txt" -   # imprime o conteúdo

# 2. Tentar reabrir via ACL -- deve falhar por causa do Bucket Owner Enforced
aws s3api put-object-acl --bucket "$BUCKET_NAME" --key receipt-teste.txt --acl public-read
# Esperado: AccessControlListNotSupported -- "The bucket does not allow ACLs"

# 3. Tentar reabrir via bucket policy pública -- deve falhar por causa do
#    Block Public Access (se isso tivesse funcionado, teria SUBSTITUÍDO a
#    policy DenyInsecureTransport inteira, já que put-bucket-policy
#    sobrescreve o documento -- é exatamente por isso que o Public Access
#    Block precisa ser uma camada independente, não uma opção)
cat > /tmp/public-policy-attempt.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AttemptPublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file:///tmp/public-policy-attempt.json
# Esperado: AccessDenied -- "...because it grants public access, blocked by
# the BlockPublicPolicy block public access setting"

# 4. Confirmar que a policy original (DenyInsecureTransport) segue intacta
aws s3api get-bucket-policy --bucket "$BUCKET_NAME" --query Policy --output text

# 5. Testar a exigência de TLS: mesma URL do passo 0, mas em HTTP puro
curl -s -o /dev/null -w "%{http_code}\n" \
  "http://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/receipt-teste.txt"   # 403

# 6. Gerar uma presigned URL para o objeto -- é isto que substitui o link
#    público do cenário: o backend do checkout (com a mesma credencial já
#    usada no aws s3 cp do passo 1) gera esta URL, curta e escopada a um
#    único objeto, e é ELA que vai no e-mail do cliente -- não o link "cru"
#    usado no passo 0.
PRESIGNED_URL=$(aws s3 presign "s3://${BUCKET_NAME}/receipt-teste.txt" --expires-in 300)
echo "$PRESIGNED_URL"

# 7. Simular o cliente: baixar via a presigned URL, sem nenhuma credencial
#    AWS -- só a URL. Funciona mesmo com Block Public Access 100% ligado e
#    ACL desativada, porque presigned URL não é uma concessão pública: é uma
#    requisição já assinada por um principal autorizado, com validade de
#    300 segundos neste exemplo. Compare com o passo 0: a mesma URL sem a
#    assinatura (a query string "?X-Amz-...") continua dando 403.
curl -s -o /dev/null -w "%{http_code}\n" "$PRESIGNED_URL"   # 200
```

Depois do teste, limpe o objeto e os arquivos temporários:

```bash
aws s3 rm "s3://${BUCKET_NAME}/receipt-teste.txt"
rm -f /tmp/receipt.txt /tmp/customer-receipts-policy.json /tmp/public-policy-attempt.json
```

### 🖥️ Repetindo os testes 2, 3 e 6 — Console (GUI)

- **ACL:** bucket → objeto `receipt-teste.txt` → aba **Permissions** → não há mais opção de editar ACL do objeto (a UI a esconde quando Bucket Owner Enforced está ativo) — a própria ausência da opção já é a prova.
- **Bucket policy pública:** bucket → **Permissions** → **Bucket policy** → **Edit** → cole o segundo JSON acima → **Save changes** → a AWS recusa com um erro citando o Block Public Access.
- **Presigned URL:** bucket → selecione o checkbox do objeto `receipt-teste.txt` → **Object actions** → **Share with a presigned URL** → defina a validade (Console permite até 7 dias) → **Create presigned URL**. A URL é copiada para a área de transferência — abra-a numa aba anônima/outro navegador para confirmar que baixa o arquivo sem nenhum login.

## 🧹 Como destruir

### 🏗️ Terraform

```bash
terraform destroy
```

> O bucket deste capítulo é criado com `force_destroy = true` — de propósito, só porque é um bucket de laboratório efêmero: garante que o `terraform destroy` funcione mesmo que ainda exista o objeto de teste da seção anterior, sem exigir um passo manual de limpeza. **Nunca** use essa configuração em um bucket de produção — ela apaga todo o conteúdo do bucket silenciosamente no destroy.

### ⌨️ AWS CLI

```bash
aws s3 rm "s3://${BUCKET_NAME}" --recursive
aws s3api delete-bucket --bucket "$BUCKET_NAME"
```

### 🖥️ Console (GUI)

1. **S3** → selecione o bucket → **Empty** → digite o nome do bucket para confirmar → **Empty**.
2. Com o bucket vazio, selecione-o novamente → **Delete** → digite o nome do bucket para confirmar → **Delete bucket**.

## 📚 Referências

- [SEC08-BP04 — Enforce access control](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_protect_data_rest_access_control.html) — AWS Well-Architected Framework, Security Pillar; cita explicitamente a revisão de bucket policies do S3 e evitar buckets públicos como prática de proteção de dados em repouso.
- [SEC09-BP02 — Enforce encryption in transit](https://docs.aws.amazon.com/wellarchitected/latest/framework/sec_protect_data_transit_encrypt.html) — AWS Well-Architected Framework, Security Pillar; base da statement `DenyInsecureTransport` implementada neste capítulo.
- CIS AWS Foundations Benchmark v3.0.0, controle 2.1.4 — *Ensure that S3 Buckets are configured with 'Block Public Access'* (mesmo número no v5.0.0; controle 2.1.5 no v1.4.0) — mapeado no AWS Security Hub como [S3.1](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-1) (nível de conta) e [S3.8](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-8) (nível de bucket).
- CIS AWS Foundations Benchmark v3.0.0, controle 2.1.1 — *Ensure S3 general purpose buckets require requests to use SSL* (mesmo número no v5.0.0; controle 2.1.2 no v1.4.0) — mapeado no AWS Security Hub como [S3.5](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-5).
- AWS Security Hub — [S3.2](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-2) / [S3.3](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-3) — bloqueio de leitura/escrita pública, a consequência prática do Public Access Block implementado neste capítulo.
- AWS Security Hub — [S3.12](https://docs.aws.amazon.com/securityhub/latest/userguide/s3-controls.html#s3-12) — *ACLs should not be used to manage user access to S3 general purpose buckets*, base da decisão de usar Bucket Owner Enforced neste capítulo.
- [Blocking public access to your Amazon S3 storage](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html) — referência oficial do recurso Block Public Access.
- [Controlling ownership of objects and disabling ACLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html) — referência oficial de Bucket Owner Enforced.
- [What S3 bucket policy should I use to comply with the AWS Config rule s3-bucket-ssl-requests-only?](https://aws.amazon.com/premiumsupport/knowledge-center/s3-bucket-policy-for-config-rule/) — modelo oficial da statement `DenyInsecureTransport` usada neste capítulo.
- [Sharing an object with a presigned URL](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html) — referência oficial do mecanismo usado para entregar o recibo ao cliente final sem exigir uma conta AWS, mantendo o bucket 100% privado.
