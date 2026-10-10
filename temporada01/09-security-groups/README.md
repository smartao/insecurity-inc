# 09 — 🧱 Security Groups

![Capa do capítulo 09 — Security Groups](../imagens/cover-S01E09.jpg)

**Arco:** Rede  
**Conceito:** Regras de rede  
**Well-Architected:** [SEC05-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_layered.html)  
**Custo:** 🟢  

## 🎬 Cenário

Os capítulos 07 e 08 arrumaram *onde* a senha do banco do checkout mora e *como* ela é trocada. Numa revisão de segurança, a analista faz a pergunta seguinte: **"tá, mas quem consegue chegar nesse banco?"**

Ninguém responde de cabeça, e abrir o Console não ajuda muito. O checkout inteiro — a camada que atende o cliente, a aplicação e o banco — usa **um único security group**, o `launch-wizard-1`, que o assistente de lançamento do EC2 criou na VPC padrão da conta na primeira noite de produção. Numa sexta à noite o checkout travou e o analista de plantão (o do capítulo 01) estava viajando: IP de hotel, depois de 4G, mudando toda hora. Sem conseguir entrar na instância pela porta 22, o fundador abriu o Console e trocou a origem da regra de SSH para **"Anywhere"** — "só até resolver o problema de acesso". A regra continua lá. Na mesma semana, o desenvolvedor abriu a 5432 no mesmo grupo para conectar do notebook — "só pra testar a migração".

O grupo, hoje, equivale a isto (não é a stack deste capítulo — é só o "antes", em Terraform, para deixar explícito):

```hcl
resource "aws_security_group" "launch_wizard_1" {
  name        = "launch-wizard-1"
  description = "launch-wizard-1 created 2026-01-09T22:14:03.512Z"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "so ate resolver o acesso"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "app do checkout"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "banco -- o dev conecta do notebook"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Ninguém "configurou errado" de propósito: cada regra resolveu um problema real, naquele momento, com um clique — e a API não reclama de nenhuma delas (Como testar, passo 3). O problema é que uma regra de firewall não tem prazo de validade.

## 🚨 O Problema

1. **Porta administrativa aberta para o mundo, "só até resolver".** Com `0.0.0.0/0` na porta 22, qualquer endereço da internet pode tentar autenticar no SSH: o que separa a instância de um atacante passa a ser uma chave (que vaza) e a versão do `sshd` (que envelhece). A regra "temporária" não expira nem avisa. É exatamente o que o CIS AWS Foundations Benchmark proíbe — **v5.0.0, requisitos 5.3 (origem `0.0.0.0/0`) e 5.4 (origem `::/0`)**: nenhum security group libera entrada, vinda de qualquer endereço, para portas de administração remota; na v3.0.0, são o 5.2 e o 5.3. No Security Hub, são os controles EC2.53 e EC2.54 (a v1.2.0 tinha um controle por porta: EC2.13 para a 22 e EC2.14 para a 3389).

   > **Um security group só expõe algo se houver caminho até ele.** Ele é um firewall na interface de rede: uma regra aberta numa instância sem IP público e sem rota para a internet não expõe nada. Só que, na VPC padrão, esse caminho já vem pronto — conferido nesta conta:
   >
   > ```bash
   > # As subnets da VPC padrão atribuem IP público na criação?
   > aws ec2 describe-subnets --filters Name=default-for-az,Values=true --query 'Subnets[].MapPublicIpOnLaunch' --output text
   >
   > # E a tabela de rotas principal dela sai para um internet gateway?
   > DEFAULT_VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
   > [ -n "$DEFAULT_VPC" ] && [ "$DEFAULT_VPC" != None ] || echo "DEFAULT_VPC VAZIA -- não continue sem corrigir (confira o login AWS; a conta pode não ter VPC padrão nesta região)"
   > aws ec2 describe-route-tables --filters Name=vpc-id,Values="$DEFAULT_VPC" Name=association.main,Values=true --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId]' --output text
   > ```
   >
   > ```text
   > True    True    True    True    True    True
   > 172.31.0.0/16    local
   > 0.0.0.0/0    igw-...
   > ```
   >
   > Seis subnets, todas dando IP público a quem nasce nelas, e uma rota `0.0.0.0/0` para o internet gateway. O `0.0.0.0/0` da regra do fundador é alcançável de verdade.

   E a **API não reclama**: testado no passo 3 de Como testar, a AWS aceita `0.0.0.0/0` na 22, `::/0` na 3389 e até a faixa inteira `0-65535`, sem erro nem aviso.
2. **Um security group para todas as camadas.** Com uma regra por porta num grupo único, "só a aplicação fala com o banco" é impossível de escrever: quem alcança o checkout alcança o banco, porque estão no mesmo grupo. O [SEC05-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_layered.html) chama isso de anti-padrão — *"você assume que todo o tráfego dentro de uma camada de rede é autenticado e autorizado"* — e classifica o risco de não adotar a prática como **alto**.
3. **CIDR onde deveria haver referência de security group.** O jeito de "resolver" o item 2 sem mexer na estrutura é escrever a regra do banco com o CIDR da VPC (`10.0.0.0/16`). Aí qualquer host da VPC — hoje ou no futuro, inclusive um comprometido ou de outro projeto — alcança a 5432, e os IPs mudam a cada autoscaling. Um security group pode, em vez disso, citar **outro security group** como origem: a regra passa a valer para os membros do grupo, sem lista de IPs para manter (o mesmo SEC05-BP02 destaca isso: *"minimizando atualizações conforme os recursos do grupo mudam"*).
4. **O default security group.** Toda VPC nasce com um, chamado `default`: libera **todo o tráfego entre os seus membros** e **toda a saída**, e recebe qualquer recurso lançado sem security group explícito. Não dá para apagá-lo (`Client.CannotDelete`), só esvaziá-lo — e é isso que o CIS pede (**v5.0.0, 5.5**; v3.0.0, 5.4; Security Hub EC2.2). Nesta conta, o default da VPC padrão tem 1 regra de entrada e 1 de saída (passo 2 de Como testar).
5. **Saída aberta para tudo.** Todo security group nasce com uma regra de saída "libera tudo", e quase ninguém mexe nela. Uma instância comprometida pode falar com qualquer endereço da internet — exfiltrar dados, buscar ferramentas, abrir um canal de comando e controle. O SEC05-BP02 lista, entre os anti-padrões, aplicar controle *"só ao tráfego de entrada ou só ao de saída, mas não aos dois"*.
6. **Nada avisa quando alguém abre de novo.** Existem controles detectivos, e nenhum está ligado: as regras gerenciadas do AWS Config `restricted-ssh` (conforme só se o SSH de entrada não vier de `0.0.0.0/0` nem `::/0`), `restricted-common-ports`, `vpc-default-security-group-closed` e `vpc-sg-open-only-to-authorized-ports`, e os controles do Security Hub por trás delas (EC2.2, EC2.18, EC2.19, além dos citados no item 1). Na Insecurity Inc. o Config só chega no capítulo 12 — e o Terraform deste capítulo, como o passo 3 mostra, também não enxerga uma regra criada por fora.

## ✅ A Correção

```text
internet ──443──▶ [ web ] ──8080──▶ [ app ] ──5432──▶ [ db ]
                                       └──443──▶ APIs da AWS (concessão documentada)
```

1. **Uma VPC só do laboratório, e um default SG zerado.** A VPC `insecurity-inc-lab` (`10.9.0.0/16`, uma subnet, sem internet gateway) existe para o capítulo poder ser destruído sem rastro e sem tocar no default SG de um recurso que já existia antes dele. O `aws_default_security_group` a adota e a deixa **sem nenhuma regra** (CIS v5.0.0, 5.5). Um detalhe que só o teste revelou: sem `ingress = []` e `egress = []` **explícitos**, o provider esvazia o grupo na primeira vez e depois nunca mais olha — uma regra `0.0.0.0/0` criada por fora dava `No changes` no `plan` e o `apply` não a removia. Com as duas listas vazias, o Terraform passa a ser **autoritativo**: a mesma regra vira deriva (`plan` sai com código 2) e o `apply` a remove (passo 4).
2. **Um security group por camada** — `insecurity-inc-checkout-web`, `-app` e `-db` —, com estas regras, e só estas:

   | Grupo | Entrada | Saída |
   | --- | --- | --- |
   | `web` | tcp **443** de `0.0.0.0/0` | tcp **8080** → SG `app` |
   | `app` | tcp **8080** ← SG `web` | tcp **5432** → SG `db`; tcp **443** → `0.0.0.0/0` |
   | `db` | tcp **5432** ← SG `app` | *(nenhuma)* |
   | `default` da VPC do lab | *(nenhuma)* | *(nenhuma)* |

3. **Entre camadas, referência de security group — nunca CIDR.** A regra do banco diz "aceito a 5432 de quem está no grupo `app`", e vale para os membros de hoje e de amanhã (pela documentação, o tráfego é identificado pelos IPs privados das interfaces de rede dos membros). Uma regra que referencia outro grupo conta como **uma** regra, não importa o tamanho do grupo referenciado. O preço: como a saída também é restrita (ponto 6), cada fluxo é descrito **duas vezes** — na saída do grupo de origem e na entrada do de destino (`web-to-app` e `app-from-web`). E não existe regra de retorno: o security group é *stateful*, a resposta a uma conexão permitida volta sozinha (o Reachability Analyzer confirma no teste opcional: o caminho de volta não cita regra nenhuma).
4. **Nenhuma regra de porta 22 — em nenhum grupo.** O problema real do fundador era "como o plantão entra na instância", e a resposta não é uma porta melhor protegida: é **não ter a porta**. O [Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) dá acesso ao shell *"sem a necessidade de abrir portas de entrada, manter bastion hosts ou gerenciar chaves SSH"*, com acesso controlado por IAM (o plantão do capítulo 01 poderia receber acesso só durante o turno), as chamadas de API auditadas no CloudTrail e o log das sessões enviável ao S3 ou ao CloudWatch Logs — exceto sessões que usam *port forwarding* ou SSH, que a documentação diz não terem esse log. Este capítulo **não constrói esse acesso** (não há instâncias): prova a ausência do buraco, não a alternativa. Ver Dívidas em aberto.
5. **O `0.0.0.0/0` que sobra é deliberado — e a auditoria sabe distinguir.** A camada web é a porta de entrada pública do checkout: HTTPS aberto para a internet é o comportamento esperado, não um defeito. Nem todo `0.0.0.0/0` é um problema; é a **porta** que decide. Por isso a consulta de auditoria do passo 0 marca `ALERTA` quando a regra aberta expõe 22, 3389 ou todos os protocolos, e `aberta` para o resto (o HTTPS da web, para um humano revisar).
6. **Saída restrita nas três camadas.** A web só fala com a app; a app só com o banco e com HTTPS; o banco não inicia conexão nenhuma. O Terraform remove a regra de saída "libera tudo" que a AWS cria com todo security group novo (testado: nenhum dos três a tem). Uma exceção, consciente: a `app` sai por 443 para `0.0.0.0/0`, porque precisa chamar APIs da AWS (o Secrets Manager do capítulo 08, por exemplo) e um security group filtra por IP e porta, **não por nome de host**. Restringir isso de verdade é assunto de VPC endpoints ou de um firewall de DNS/de rede — o próprio SEC05-BP02 aponta o Route 53 Resolver DNS Firewall e o Network Firewall para esse papel. (DNS não precisa de regra: a documentação diz que o security group não tem efeito sobre o tráfego DNS para o Route 53 Resolver.)
7. **Regras em recursos separados, não inline.** Cada regra é um `aws_vpc_security_group_ingress_rule` / `egress_rule`, e não um bloco `ingress`/`egress` dentro do `aws_security_group`, por dois motivos: a web referencia a app na saída e a app referencia a web na entrada — com regras inline isso vira um ciclo de dependência que o Terraform não resolve; e cada regra ganha ID (`sgr-...`) e tags próprios. O custo é uma **cegueira** deliberadamente exposta: o Terraform só olha as regras que ele mesmo criou, então uma a mais, criada por fora num desses três grupos, **não aparece no `plan`** (passo 3, testado). Misturar os dois estilos no mesmo grupo é pior: o provider avisa que causa conflitos e diferenças perpétuas. A compensação, por enquanto, é a consulta de auditoria; a de verdade são o Config e o EventBridge (capítulos 12 e 13).
8. **Três ENIs de exemplo, sem instância.** Um security group é associado a uma **interface de rede**, não a "uma máquina". As três ENIs (`web`, `app` e `db`), sem instância nenhuma, existem para os grupos terem algo associado e para o teste opcional (o Reachability Analyzer aceita ENIs como origem e destino — testado). ENIs sem instância não aparecem entre os componentes cobrados na documentação de preços do VPC.
9. **Descrições sem acento.** O EC2 rejeita qualquer caractere fora do ASCII numa descrição de security group ou de regra (`InvalidParameterValue`, passo 5). É por isso que as descrições no Terraform e na CLI deste capítulo estão sem acento, num repositório em português. E `description` (assim como `name` e `vpc_id`) força a recriação do grupo se mudar — e um grupo em uso por uma ENI não pode ser apagado, então a troca exige cuidado (o [provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) sugere `create_before_destroy`).

> **Limitação deliberada — leia antes de tirar conclusões.** Este laboratório não tem instância, internet gateway, NAT nem tráfego real: nada nele é alcançável da internet, com ou sem `0.0.0.0/0` nas regras. O capítulo prova **as regras** — o que a AWS guardou, o que ela aceita sem reclamar, o que o Terraform enxerga —, e, no teste opcional, o veredito do motor de análise da própria AWS (Reachability Analyzer) sobre o caminho entre as camadas. Não prova tráfego real de rede.

**Dívidas em aberto.**

- **A VPC padrão da conta continua como estava.** O capítulo cria e destrói a própria VPC; o default SG da VPC padrão — 1 regra de entrada e 1 de saída, como o passo 2 mostra — segue reprovando o CIS 5.5 / EC2.2. Esvaziá-lo (ou apagar a VPC padrão nas regiões que a conta não usa) é decisão de conta, não de laboratório.
- **Um security group filtra por IP e porta, não por nome.** A saída `443 → 0.0.0.0/0` da `app` fica como concessão até haver VPC endpoints ou inspeção (SEC05-BP03).
- **Remover uma regra não derruba as conexões já estabelecidas.** Segundo a [documentação de connection tracking](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-connection-tracking.html), *"quando você muda uma regra, as conexões rastreadas dela não são interrompidas imediatamente"* — o security group continua permitindo pacotes até a conexão expirar. Há uma exceção que pesa no "antes": um fluxo é **não rastreado** quando há uma regra que permite todo o tráfego (`0.0.0.0/0`) e uma regra na outra direção que permite toda a resposta em qualquer porta — e aí remover a regra o derruba na hora. Foi o cenário do fundador (22 aberto + saída "libera tudo"); no desenho corrigido nenhum fluxo cai nessa exceção, então fechar uma regra durante um incidente **não** derruba a sessão que um atacante já abriu. Para cortar na hora, a própria documentação aponta a *network ACL* (stateless) da subnet. Não testado aqui: exige uma instância.
- **Detecção e prevenção.** Nada avisa se alguém abrir de novo (Config no capítulo 12, EventBridge no 13), e exigir isso de **todo mundo** é trabalho de um guardrail organizacional (SCP, capítulo 14) — com um limite que a própria AWS documenta: ao autorizar/revogar regras, ela *não avalia o IAM contra o security group referenciado*, então uma policy não consegue controlar **quais** grupos podem ser citados como origem.
- **O acesso do plantão ainda precisa ser construído.** O Session Manager exige o SSM Agent, uma instance profile com permissões de SSM e conectividade com os endpoints do serviço (IP público e internet gateway, NAT ou VPC endpoints de interface — estes últimos com custo). Nada disso existe aqui.
- **Camadas de rede.** Uma subnet só, sem separação pública/privada, sem tabelas de rota por camada e sem network ACL além da padrão: é o assunto do SEC05-BP01, num capítulo à parte.

## 🧪 Como aplicar

Três caminhos equivalentes — escolha o que fizer sentido para você. Os três criam os mesmos recursos, com os mesmos nomes, então dá para misturar (com a ressalva de que o `terraform destroy` só conhece o que o Terraform criou).

> **Custo:** zero. A [documentação de preços do VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html#pricing) é explícita — *"não há cobrança adicional por usar uma VPC"* — e lista o que cobra (NAT gateways, tráfego espelhado, Reachability Analyzer, entre outros): nada disso está no caminho principal. O único gasto possível é o **teste opcional** do Reachability Analyzer (US$0,10 por análise; ver Como testar).

### 🏗️ Opção 1 — Terraform (caminho testado neste repo)

```bash
terraform init
terraform apply
```

Testado com Terraform 1.16.1 e provider AWS 5.100.0 (o código pede `>= 1.7` e `~> 5.0`). Cria 15 recursos: a VPC, a subnet, o default SG esvaziado, os três grupos, as seis regras e as três ENIs.

### ⌨️ Opção 2 — AWS CLI

Precisa do `jq` (usado para montar o `--ip-permissions`). Cole o bloco inteiro num shell só — as variáveis (`VPC_ID`, `WEB_SG`...) passam de um passo para o outro.

```bash
REGION=$(aws configure get region)
AZ=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
for v in REGION AZ; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (confira o login AWS e o 'aws configure')"; done

# Tags do capítulo (as mesmas do Terraform) mais o Name. Uso: tagspec TIPO NOME
tagspec() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=project,Value=insecurity-inc},{Key=env,Value=lab},{Key=chapter,Value=09}]"; }

# Monta o --ip-permissions de uma regra TCP de porta única.
# Uso: perm PORTA cidr CIDR "descrição"  ou  perm PORTA sg ID-DO-SG "descrição"
perm() { jq -nc --argjson p "$1" --arg k "$2" --arg v "$3" --arg d "$4" '[{IpProtocol:"tcp",FromPort:$p,ToPort:$p} + (if $k=="cidr" then {IpRanges:[{CidrIp:$v,Description:$d}]} else {UserIdGroupPairs:[{GroupId:$v,Description:$d}]} end)]'; }

# 1. VPC dedicada e uma subnet
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.9.0.0/16 \
  --tag-specifications "$(tagspec vpc insecurity-inc-lab)" \
  --query Vpc.VpcId --output text)
SUBNET_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.9.1.0/24 --availability-zone "$AZ" \
  --tag-specifications "$(tagspec subnet insecurity-inc-lab)" \
  --query Subnet.SubnetId --output text)
for v in VPC_ID SUBNET_ID; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (o create falhou)"; done

# 2. Esvazia o default security group da VPC. Ele nasce com uma regra de entrada
#    ("libera tudo entre os membros do próprio grupo") e uma de saída ("libera
#    tudo"); as duas saem pelo ID.
DEFAULT_SG=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text)
DEFAULT_IN=$(aws ec2 describe-security-group-rules --filters Name=group-id,Values="$DEFAULT_SG" --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' --output text)
DEFAULT_OUT=$(aws ec2 describe-security-group-rules --filters Name=group-id,Values="$DEFAULT_SG" --query 'SecurityGroupRules[?IsEgress==`true`].SecurityGroupRuleId' --output text)
for v in DEFAULT_SG DEFAULT_IN DEFAULT_OUT; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (o default SG não foi encontrado)"; done
aws ec2 revoke-security-group-ingress --group-id "$DEFAULT_SG" --security-group-rule-ids "$DEFAULT_IN" > /dev/null
aws ec2 revoke-security-group-egress --group-id "$DEFAULT_SG" --security-group-rule-ids "$DEFAULT_OUT" > /dev/null
aws ec2 create-tags --resources "$DEFAULT_SG" --tags Key=Name,Value=insecurity-inc-lab-default-nao-usar Key=project,Value=insecurity-inc Key=env,Value=lab Key=chapter,Value=09

# 3. Um security group por camada. As descrições não podem ter acento (o EC2
#    rejeita qualquer caractere fora do ASCII -- passo 5 de Como testar).
WEB_SG=$(aws ec2 create-security-group --group-name insecurity-inc-checkout-web \
  --description "Camada web do checkout - unica que aceita trafego da internet, so HTTPS" \
  --vpc-id "$VPC_ID" --tag-specifications "$(tagspec security-group insecurity-inc-checkout-web)" \
  --query GroupId --output text)
APP_SG=$(aws ec2 create-security-group --group-name insecurity-inc-checkout-app \
  --description "Camada app do checkout - so aceita trafego vindo da camada web" \
  --vpc-id "$VPC_ID" --tag-specifications "$(tagspec security-group insecurity-inc-checkout-app)" \
  --query GroupId --output text)
DB_SG=$(aws ec2 create-security-group --group-name insecurity-inc-checkout-db \
  --description "Camada de banco do checkout - so aceita trafego vindo da camada app" \
  --vpc-id "$VPC_ID" --tag-specifications "$(tagspec security-group insecurity-inc-checkout-db)" \
  --query GroupId --output text)
for v in WEB_SG APP_SG DB_SG; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (o create-security-group falhou)"; done

# Todo security group novo nasce com uma regra de saída "libera tudo". O
# Terraform a remove sozinho; na CLI, é por sua conta.
for sg in "$WEB_SG" "$APP_SG" "$DB_SG"; do
  aws ec2 revoke-security-group-egress --group-id "$sg" --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0}]' > /dev/null
done

# 4. As seis regras -- entre camadas, sempre por referência de security group
aws ec2 authorize-security-group-ingress --group-id "$WEB_SG" \
  --ip-permissions "$(perm 443 cidr 0.0.0.0/0 'HTTPS da internet - unica regra publica do capitulo')" \
  --tag-specifications "$(tagspec security-group-rule web-https-from-internet)" > /dev/null
aws ec2 authorize-security-group-egress --group-id "$WEB_SG" \
  --ip-permissions "$(perm 8080 sg "$APP_SG" 'Encaminha para a camada app, so na porta da aplicacao')" \
  --tag-specifications "$(tagspec security-group-rule web-to-app)" > /dev/null

aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
  --ip-permissions "$(perm 8080 sg "$WEB_SG" 'Porta da aplicacao, so vinda da camada web')" \
  --tag-specifications "$(tagspec security-group-rule app-from-web)" > /dev/null
aws ec2 authorize-security-group-egress --group-id "$APP_SG" \
  --ip-permissions "$(perm 5432 sg "$DB_SG" 'Porta do banco, so para a camada de banco')" \
  --tag-specifications "$(tagspec security-group-rule app-to-db)" > /dev/null
aws ec2 authorize-security-group-egress --group-id "$APP_SG" \
  --ip-permissions "$(perm 443 cidr 0.0.0.0/0 'HTTPS de saida para APIs da AWS - ver README, dividas em aberto')" \
  --tag-specifications "$(tagspec security-group-rule app-https-out)" > /dev/null

aws ec2 authorize-security-group-ingress --group-id "$DB_SG" \
  --ip-permissions "$(perm 5432 sg "$APP_SG" 'Porta do banco, so vinda da camada app')" \
  --tag-specifications "$(tagspec security-group-rule db-from-app)" > /dev/null
# (o db não tem regra de saída, de propósito)

# 5. Uma interface de rede de exemplo por camada (sem instância -- ver Correção)
aws ec2 create-network-interface --subnet-id "$SUBNET_ID" --groups "$WEB_SG" \
  --description "Placeholder da camada web do checkout (sem instancia) - capitulo 09" \
  --tag-specifications "$(tagspec network-interface insecurity-inc-checkout-web)" \
  --query NetworkInterface.NetworkInterfaceId --output text
aws ec2 create-network-interface --subnet-id "$SUBNET_ID" --groups "$APP_SG" \
  --description "Placeholder da camada app do checkout (sem instancia) - capitulo 09" \
  --tag-specifications "$(tagspec network-interface insecurity-inc-checkout-app)" \
  --query NetworkInterface.NetworkInterfaceId --output text
aws ec2 create-network-interface --subnet-id "$SUBNET_ID" --groups "$DB_SG" \
  --description "Placeholder da camada de banco do checkout (sem instancia) - capitulo 09" \
  --tag-specifications "$(tagspec network-interface insecurity-inc-checkout-db)" \
  --query NetworkInterface.NetworkInterfaceId --output text
```

### 🖥️ Opção 3 — Console (GUI)

Os security groups que se referenciam só podem citar grupos que já existem — por isso os três grupos são criados **vazios** primeiro (passo 4), e as regras entram depois (passo 5).

1. **Criar a VPC:** console **VPC** → **Your VPCs** → **Create VPC** → **VPC only** → **Name tag** `insecurity-inc-lab`, **IPv4 CIDR** `10.9.0.0/16`, sem bloco IPv6 → tags `project=insecurity-inc`, `env=lab`, `chapter=09` → **Create VPC**.
2. **Criar a subnet:** **VPC** → **Subnets** → **Create subnet** → a VPC do passo 1 → nome `insecurity-inc-lab`, uma zona de disponibilidade qualquer, **IPv4 subnet CIDR block** `10.9.1.0/24` → as mesmas três tags → **Create subnet**. Não crie internet gateway nem tabela de rotas extra.
3. **Esvaziar o default security group da VPC:** **EC2** → **Security Groups** → o grupo `default` cuja coluna **VPC ID** é a do laboratório → aba **Inbound rules** → **Edit inbound rules** → remova a única regra (*All traffic*, origem o próprio grupo) → **Save rules**. Aba **Outbound rules** → **Edit outbound rules** → remova a única regra (*All traffic*, `0.0.0.0/0`) → **Save rules**. Opcional: dê a ele o nome `insecurity-inc-lab-default-nao-usar` e as tags do capítulo.
4. **Criar os três security groups vazios:** **EC2** → **Security Groups** → **Create security group**, três vezes, sempre com a VPC do laboratório e as tags `project=insecurity-inc`, `env=lab`, `chapter=09`. **Sem acento nas descrições** — a API rejeita qualquer caractere fora do ASCII (passo 5 de Como testar):

   | Nome | Descrição |
   | --- | --- |
   | `insecurity-inc-checkout-web` | `Camada web do checkout - unica que aceita trafego da internet, so HTTPS` |
   | `insecurity-inc-checkout-app` | `Camada app do checkout - so aceita trafego vindo da camada web` |
   | `insecurity-inc-checkout-db` | `Camada de banco do checkout - so aceita trafego vindo da camada app` |

   Em **Outbound rules**, o formulário pode vir com uma regra *All traffic* para `0.0.0.0/0` já preenchida (é a que a AWS cria em todo grupo novo): se aparecer, **remova-a**. Deixe **Inbound rules** vazio por enquanto.
5. **Adicionar as seis regras** (em cada grupo: **Edit inbound rules** / **Edit outbound rules** → **Add rule** → **Save rules**). Em *Type*, use **Custom TCP**; nas regras entre camadas, o *Source* / *Destination* é **Custom**, e você escolhe o **security group** (não digite um CIDR):

   | Grupo | Direção | Porta | Origem / destino | Descrição |
   | --- | --- | --- | --- | --- |
   | `web` | Inbound | 443 | `0.0.0.0/0` | `HTTPS da internet - unica regra publica do capitulo` |
   | `web` | Outbound | 8080 | SG `insecurity-inc-checkout-app` | `Encaminha para a camada app, so na porta da aplicacao` |
   | `app` | Inbound | 8080 | SG `insecurity-inc-checkout-web` | `Porta da aplicacao, so vinda da camada web` |
   | `app` | Outbound | 5432 | SG `insecurity-inc-checkout-db` | `Porta do banco, so para a camada de banco` |
   | `app` | Outbound | 443 | `0.0.0.0/0` | `HTTPS de saida para APIs da AWS - ver README, dividas em aberto` |
   | `db` | Inbound | 5432 | SG `insecurity-inc-checkout-app` | `Porta do banco, so vinda da camada app` |

   O `db` fica **sem** regra de saída. Opcional: dê a cada regra a tag `Name` (`web-https-from-internet`, `web-to-app`, `app-from-web`, `app-to-db`, `app-https-out`, `db-from-app`), como no Terraform e na CLI.
6. **Criar as três interfaces de rede:** **EC2** → **Network Interfaces** → **Create network interface**, três vezes → *Description* `Placeholder da camada web do checkout (sem instancia) - capitulo 09` (e `app`, `de banco`, respectivamente) → **Subnet**: a do laboratório → **Security groups**: o grupo da camada, e só ele (remova o `default`, se o formulário o preencher) → tag `Name` = o nome do grupo (`insecurity-inc-checkout-web`...) e as tags do capítulo → **Create network interface**.

## 🧾 Como testar

O objetivo é provar, na prática, quatro coisas: o que foi criado é exatamente o que o código declara — as regras entre camadas citam **grupos**, não CIDRs, e o default está zerado (passos 0 a 2); a AWS aceita em silêncio uma regra ruim e o Terraform **não a enxerga** nos grupos das camadas, mas **enxerga** no default (passos 3 e 4); duas pegadinhas de API que moldam o código e a ordem de destruição (passos 5 e 6); e o estado final está limpo (passo 7). Ao final, um teste **opcional e pago** (US$0,30) confirma o enforcement com o motor de análise da própria AWS.

Requer `jq` e o Terraform, e deve rodar **dentro da pasta do capítulo**. **Cole o bloco inteiro num shell só**, de uma vez — os passos 3, 4 e 6 **mudam a infra ao vivo** e a revertem no fim do próprio passo (o comentário `REVERT` marca onde), usando variáveis (`$BAD_ALL`, `$BAD_V4`...) capturadas em passos anteriores *na mesma sessão*. Colar só um trecho isolado — o REVERT sozinho, por exemplo, numa aba nova ou depois de fechar o terminal — deixa essas variáveis vazias: o `revoke-security-group-ingress` falha inteiro com `InvalidSecurityGroupRuleId.Malformed` (a AWS rejeita a chamada toda se um dos IDs vier vazio) e **nenhuma das regras ruins é revogada** — a auditoria seguinte ainda mostra os `ALERTA`. Se isso acontecer, rode `aws ec2 describe-security-group-rules --filters Name=group-id,Values=$APP_SG` para pegar os IDs reais das regras `teste-nao-faca-isto` que sobraram e revogue-as à mão. Nos passos 0, 3 e 4, o `terraform plan` só faz sentido para quem aplicou pelo Terraform; para quem seguiu a CLI ou o Console, os demais passos valem igual — basta preencher à mão as cinco variáveis do início (os IDs aparecem em **EC2** → **Security Groups**). Numa conta com outras cargas de trabalho, a consulta de auditoria pode listar mais linhas `aberta` além do HTTPS da web; o que importa é não haver `ALERTA` inesperado.

```bash
WEB_SG=$(terraform output -raw web_security_group_id)
APP_SG=$(terraform output -raw app_security_group_id)
DB_SG=$(terraform output -raw db_security_group_id)
DEFAULT_SG=$(terraform output -raw default_security_group_id)
VPC_ID=$(terraform output -raw vpc_id)

# Guardrail: avisa se alguma variável ficou vazia (ou "None"). Sem ele, rodar o
# bloco fora da pasta do capítulo passa em branco: o "terraform output" não acha
# o state e as variáveis ficam vazias sem erro.
for v in WEB_SG APP_SG DB_SG DEFAULT_SG VPC_ID; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (rode dentro da pasta do capítulo e confira o login AWS)"; done

# ID do grupo -> nome, para os relatórios abaixo mostrarem nomes em vez de sg-...
sg_names() {
  aws ec2 describe-security-groups --query 'SecurityGroups[].[GroupId,GroupName]' --output json | jq 'map({(.[0]): .[1]}) | add'
}

# Consulta de auditoria: toda regra de ENTRADA aberta para 0.0.0.0/0 ou ::/0 em
# QUALQUER security group da região, marcada ALERTA quando expõe porta
# administrativa (22 ou 3389, isolada ou dentro de uma faixa) ou todos os
# protocolos. Faz o papel das regras do AWS Config (restricted-ssh etc.) que só
# chegam no capítulo 12. Usa jq sobre describe-security-group-rules, e não o
# filtro ip-permission.* do describe-security-groups, porque esse filtro só casa
# porta EXATA: uma faixa como "0-65535" passaria batido (passo 3a).
audit_open_ingress() {
  local NAMES
  NAMES=$(sg_names)
  aws ec2 describe-security-group-rules --output json | jq -r --argjson names "$NAMES" '
    [ .SecurityGroupRules[]
      | select(.IsEgress == false and (.CidrIpv4 == "0.0.0.0/0" or .CidrIpv6 == "::/0"))
      | ((.IpProtocol == "-1")
         or ((.IpProtocol == "tcp" or .IpProtocol == "6")
             and ((.FromPort <= 22 and .ToPort >= 22) or (.FromPort <= 3389 and .ToPort >= 3389)))) as $admin
      | [(if $admin then "ALERTA" else "aberta" end), $names[.GroupId], .SecurityGroupRuleId, .IpProtocol, (if .IpProtocol == "-1" then "todas" else "\(.FromPort)-\(.ToPort)" end), (.CidrIpv4 // .CidrIpv6)] ]
    | sort_by(.[0], .[1], .[4], .[3], .[2]) | .[] | @tsv'
}

PLAN_TXT=$(mktemp)

# 0. Pré-condição: estado vivo == Terraform, e nenhuma regra aberta pendurada de
#    um teste interrompido (os passos 3 e 4 acrescentam regras ruins de
#    propósito e as revertem; se um deles parou no meio, o resto mentiria).
terraform plan -detailed-exitcode > /dev/null; echo "plan exit=$?  (0 = sem deriva; 2 = há deriva: corrija antes de testar)"
audit_open_ingress
# Esperado: exit=0 e UMA linha só, "aberta  insecurity-inc-checkout-web  sgr-...
# tcp  443-443  0.0.0.0/0" -- o HTTPS público da camada web. Nenhum ALERTA.

# 1. Inventário: as regras de cada camada. Entre camadas, a origem/destino é o
#    NOME de um security group, nunca um CIDR; os dois únicos CIDRs são o HTTPS
#    da web (entrada) e o HTTPS de saída da app.
NAMES=$(sg_names)
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$WEB_SG","$APP_SG","$DB_SG" --output json | jq -r --argjson names "$NAMES" '
  .SecurityGroupRules | sort_by($names[.GroupId], .IsEgress, .FromPort) | .[]
  | [$names[.GroupId], (if .IsEgress then "saída  " else "entrada" end), .IpProtocol, "\(.FromPort)-\(.ToPort)", (.CidrIpv4 // $names[.ReferencedGroupInfo.GroupId] // .CidrIpv6), .Description]
  | @tsv'
# Esperado: 6 linhas, exatamente a tabela da seção Correção. O db não tem
# nenhuma linha "saída" -- e a regra padrão "libera toda saída" que a AWS cria
# junto com todo security group novo não aparece em nenhum dos três.

# 2. Os default security groups da região: o do laboratório está zerado; o da VPC
#    padrão da conta, não (CIS v5.0.0, 5.5 / Security Hub EC2.2).
aws ec2 describe-security-groups --filters Name=group-name,Values=default \
  --query 'SecurityGroups[].{Grupo:GroupId,Vpc:VpcId,Entrada:length(IpPermissions),Saida:length(IpPermissionsEgress)}' --output table
# Esperado: o default do laboratório com 0 e 0. O da VPC padrão (172.31.0.0/16)
# com 1 e 1: entrada liberada entre os membros do próprio grupo e saída liberada
# para tudo. É dívida da conta, fora do escopo do Terraform deste capítulo.

# 3. A AWS aceita regras ruins em silêncio, num security group que o Terraform
#    gerencia: primeiro uma faixa "0-65535" de IPv4 (o "abre tudo só pra
#    testar"), depois a 22 de IPv4 e a 3389 de IPv6. (Muda o SG da app e
#    REVERTE no fim do passo.)
BAD_ALL=$(aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
  --ip-permissions 'IpProtocol=tcp,FromPort=0,ToPort=65535,IpRanges=[{CidrIp=0.0.0.0/0,Description=teste-nao-faca-isto}]' \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
[ -n "$BAD_ALL" ] && [ "$BAD_ALL" != None ] || echo "BAD_ALL VAZIA -- o authorize falhou; nada foi criado, pule para o passo 4"

# 3a. Só a faixa existe por enquanto. O filtro nativo do CLI (o que a maioria
#     dos exemplos usa) casa a porta EXATA, então não enxerga uma faixa:
aws ec2 describe-security-groups --group-ids "$APP_SG" \
  --filters Name=ip-permission.cidr,Values=0.0.0.0/0 Name=ip-permission.from-port,Values=22 Name=ip-permission.to-port,Values=22 \
  --query 'SecurityGroups[].GroupName' --output json
audit_open_ingress
# Esperado: o filtro nativo devolve [] -- passa batido, embora a faixa 0-65535
# contenha a 22, a 3389 e todo o resto. A consulta de auditoria acusa ALERTA
# para ela, ao lado da linha do HTTPS da web.

# 3b. Agora a 22 (IPv4) e a 3389 (IPv6)
BAD_V4=$(aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
  --ip-permissions 'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0,Description=teste-nao-faca-isto}]' \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
BAD_V6=$(aws ec2 authorize-security-group-ingress --group-id "$APP_SG" \
  --ip-permissions 'IpProtocol=tcp,FromPort=3389,ToPort=3389,Ipv6Ranges=[{CidrIpv6=::/0,Description=teste-nao-faca-isto}]' \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
for v in BAD_V4 BAD_V6; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- o authorize falhou; nada foi criado, pule para o passo 4"; done
echo "regras criadas: $BAD_V4 $BAD_V6"
# Esperado: dois IDs sgr-..., sem erro nem aviso. Problema 1, na prática.

audit_open_ingress
# Esperado: a linha do HTTPS da web e TRÊS linhas ALERTA na camada app: a faixa
# tcp 0-65535 de 0.0.0.0/0, a tcp 22-22 de 0.0.0.0/0 e a tcp 3389-3389 de ::/0
# -- a consulta pega IPv4 e IPv6, porta isolada e faixa.

terraform plan -detailed-exitcode -no-color > "$PLAN_TXT"; echo "plan exit=$?  (0 = o Terraform NÃO enxergou as regras)"
grep -E '^(No changes|Plan:)' "$PLAN_TXT"
# Esperado: exit=0 e "No changes" -- o Terraform está cego. As regras vivem em
# recursos separados (aws_vpc_security_group_ingress_rule): ele só olha as que
# ele mesmo criou, e uma a mais, criada por fora, não é deriva para ele.

# REVERT -- sempre, mesmo se algum passo acima falhou:
# Guardrail: as três variáveis abaixo foram capturadas nos passos 3a/3b, ACIMA
# NESTE MESMO BLOCO. Se você colou só este trecho isolado (uma aba nova, um
# shell reaberto), elas chegam vazias aqui e o revoke falha por inteiro
# (InvalidSecurityGroupRuleId.Malformed), sem revogar NENHUMA regra -- a AWS
# rejeita a chamada toda se um dos IDs vier em branco.
for v in APP_SG BAD_ALL BAD_V4 BAD_V6; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue: rode o bloco inteiro de uma vez, desde o passo 3, na MESMA sessão de shell; ou revogue à mão com 'aws ec2 describe-security-group-rules --filters Name=group-id,Values=$APP_SG' para achar os IDs das regras 'teste-nao-faca-isto' que sobraram"; done
aws ec2 revoke-security-group-ingress --group-id "$APP_SG" --security-group-rule-ids "$BAD_ALL" "$BAD_V4" "$BAD_V6" --query Return --output text
audit_open_ingress
# Esperado: "True" e, de novo, uma linha só (o HTTPS da web).

# 4. No default security group é o contrário: o Terraform é autoritativo.
BAD_DEF=$(aws ec2 authorize-security-group-ingress --group-id "$DEFAULT_SG" \
  --ip-permissions 'IpProtocol=-1,IpRanges=[{CidrIp=0.0.0.0/0,Description=teste-nao-faca-isto}]' \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
[ -n "$BAD_DEF" ] && [ "$BAD_DEF" != None ] || echo "BAD_DEF VAZIA -- o authorize falhou; nada foi criado, pule para o passo 5"

audit_open_ingress
# Esperado: a linha do HTTPS da web e um ALERTA no grupo "default" (todos os
# protocolos, de 0.0.0.0/0).

terraform plan -detailed-exitcode -no-color > "$PLAN_TXT"; echo "plan exit=$?  (2 = deriva detectada)"
grep -E '^(No changes|Plan:)' "$PLAN_TXT"
# Esperado: exit=2 e "Plan: 0 to add, 1 to change, 0 to destroy" -- o plan quer
# remover a regra. (No plan completo, o aws_default_security_group.lab aparece
# com "~ ingress" e a regra marcada com "-".)

# REVERT: o próprio apply remove a regra -- é a diferença para o passo 3.
terraform apply -auto-approve -no-color > "$PLAN_TXT"; echo "apply exit=$?"
grep -E '^(Apply complete|Error)' "$PLAN_TXT"
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$DEFAULT_SG" --query 'length(SecurityGroupRules)' --output text
# Esperado: exit=0, "Apply complete! Resources: 0 added, 1 changed, 0
# destroyed." e 0 regras no default.

# 5. Descrição com acento (ou qualquer caractere fora do ASCII) é rejeitada
aws ec2 create-security-group --group-name insecurity-inc-tmp-acento --description "descrição com acento" --vpc-id "$VPC_ID"
# Esperado: InvalidParameterValue ... "Character sets beyond ASCII are not
# supported". Nada é criado. Por isso as descrições do Terraform e do CLI
# deste capítulo não têm acento.

# 6. Dois security groups que se referenciam não podem ser apagados. (Cria dois
#    grupos temporários e apaga os dois no fim do passo.)
TMP_A=$(aws ec2 create-security-group --group-name insecurity-inc-tmp-a --description "temporario a" --vpc-id "$VPC_ID" --query GroupId --output text)
TMP_B=$(aws ec2 create-security-group --group-name insecurity-inc-tmp-b --description "temporario b" --vpc-id "$VPC_ID" --query GroupId --output text)
for v in TMP_A TMP_B; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- o create-security-group falhou; não continue"; done
aws ec2 authorize-security-group-ingress --group-id "$TMP_A" --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,UserIdGroupPairs=[{GroupId=$TMP_B}]" > /dev/null
TMP_B_RULE=$(aws ec2 authorize-security-group-ingress --group-id "$TMP_B" --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,UserIdGroupPairs=[{GroupId=$TMP_A}]" --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text)
aws ec2 delete-security-group --group-id "$TMP_A"
aws ec2 delete-security-group --group-id "$TMP_B"
# Esperado: DependencyViolation nos dois ("has a dependent object"): A é
# referenciado pela regra de B, e B pela regra de A. Nenhum dos dois sai antes
# de alguém revogar uma das regras.

# REVERT (também é o jeito certo de desfazer o impasse): revoga a regra de B e
# apaga os dois.
aws ec2 revoke-security-group-ingress --group-id "$TMP_B" --security-group-rule-ids "$TMP_B_RULE" --query Return --output text
aws ec2 delete-security-group --group-id "$TMP_A" --query Return --output text
aws ec2 delete-security-group --group-id "$TMP_B" --query Return --output text
# Esperado: "True" nos três. Sem a regra de B, o A deixa de ser referenciado e
# pode ser apagado; o B, que ficou sem referência quando o A saiu, vai atrás.

# 7. Estado final: sem deriva, sem regra aberta além do HTTPS da web, default
#    zerado, e só os três grupos do capítulo sobrando.
terraform plan -detailed-exitcode > /dev/null; echo "plan exit=$?  (0 = sem deriva)"
audit_open_ingress
aws ec2 describe-security-group-rules --filters Name=group-id,Values="$DEFAULT_SG" --query 'length(SecurityGroupRules)' --output text
aws ec2 describe-security-groups --filters "Name=group-name,Values=insecurity-inc*" --query 'SecurityGroups[].GroupName' --output text
# Esperado: exit=0; a linha única do HTTPS da web; 0; e os três nomes
# insecurity-inc-checkout-{web,app,db} (nenhum insecurity-inc-tmp-*).

rm -f "$PLAN_TXT"
```

### 🔬 Teste opcional — Reachability Analyzer (US$0,10 por análise)

Tudo acima prova o que está **configurado**. Este teste pergunta à própria AWS o que **acontece** com o tráfego entre as camadas: o [Reachability Analyzer](https://docs.aws.amazon.com/vpc/latest/reachability/what-is-reachability-analyzer.html) analisa a configuração (security groups, network ACLs, rotas) de um caminho entre dois recursos e diz se ele existe — sem mandar um pacote e, o que importa aqui, **sem instância**: ele aceita interfaces de rede como origem e destino (testado com as três ENIs do capítulo).

> **Custo:** a [tabela de preços do VPC](https://aws.amazon.com/vpc/pricing/) cobra **US$0,10 por análise processada**. O bloco abaixo roda **três** análises: **US$0,30** no total. Criar e apagar o *path* é grátis, e a função `reach` apaga tanto a análise quanto o path no fim de cada rodada — não sobra nada para limpar (nem para cobrar). Se preferir, pule este teste: os passos anteriores já provam o que o capítulo se propõe a provar.

Cada rodada responde: *"a interface ORIGEM alcança a interface DESTINO na porta TCP N?"*. As três perguntas: a app alcança o banco na 5432 (o fluxo legítimo); a **web** alcança o banco na 5432 (a camada de entrada pulando a app); e a app alcança o banco na **22** (a porta que o fundador tinha aberto).

```bash
WEB_ENI=$(terraform output -raw web_network_interface_id)
APP_ENI=$(terraform output -raw app_network_interface_id)
DB_ENI=$(terraform output -raw db_network_interface_id)
NAMES=$(aws ec2 describe-security-groups --query 'SecurityGroups[].[GroupId,GroupName]' --output json | jq 'map({(.[0]): .[1]}) | add')

# Guardrail: avisa se alguma variável ficou vazia (ou "None"/"null").
for v in WEB_ENI APP_ENI DB_ENI NAMES; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] && [ "$val" != null ] || echo "$v VAZIA -- não continue sem corrigir (rode dentro da pasta do capítulo e confira o login AWS)"; done

# Uma análise: "a interface ORIGEM alcança a interface DESTINO na porta TCP N?".
# Uso: reach ORIGEM DESTINO PORTA. Cria o path, roda a análise (US$0,10), imprime
# o veredito com as regras que decidiram e apaga análise e path -- não sobra nada
# para limpar (criar e apagar o path é grátis; só a análise cobra).
reach() {
  local NIP NIA RESULT STATUS i
  NIP=$(aws ec2 create-network-insights-path --source "$1" --destination "$2" --protocol tcp --destination-port "$3" \
    --tag-specifications 'ResourceType=network-insights-path,Tags=[{Key=project,Value=insecurity-inc},{Key=env,Value=lab},{Key=chapter,Value=09}]' \
    --query NetworkInsightsPath.NetworkInsightsPathId --output text)
  [ -n "$NIP" ] && [ "$NIP" != None ] || { echo "NIP VAZIO -- o create-network-insights-path falhou; não continue"; return 1; }
  NIA=$(aws ec2 start-network-insights-analysis --network-insights-path-id "$NIP" --query NetworkInsightsAnalysis.NetworkInsightsAnalysisId --output text)
  [ -n "$NIA" ] && [ "$NIA" != None ] || { echo "NIA VAZIO -- o start-network-insights-analysis falhou; apagando o path"; aws ec2 delete-network-insights-path --network-insights-path-id "$NIP" > /dev/null; return 1; }
  for i in $(seq 1 40); do
    RESULT=$(aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$NIA" --output json)
    STATUS=$(echo "$RESULT" | jq -r '.NetworkInsightsAnalyses[0].Status')
    [ "$STATUS" != running ] && break
    sleep 3
  done
  echo "$RESULT" | jq -r --argjson names "$NAMES" '
    .NetworkInsightsAnalyses[0]
    | "alcançável=\(.NetworkPathFound)",
      ( .ForwardPathComponents[]?
        | select(.SecurityGroupRule != null)
        | "  liberou: \($names[.Component.Id] // .Component.Id) \(.SecurityGroupRule.Direction) \(.SecurityGroupRule.Protocol) \(.SecurityGroupRule.PortRange.From)-\(.SecurityGroupRule.PortRange.To) (referência: \($names[.SecurityGroupRule.SecurityGroupId // ""] // .SecurityGroupRule.Cidr))" ),
      ( .Explanations[]?
        | "  barrou: \(.Direction) em \($names[.SecurityGroups[0].Id] // .SecurityGroups[0].Id) (\(.ExplanationCode))" )'
  aws ec2 delete-network-insights-analysis --network-insights-analysis-id "$NIA" > /dev/null
  aws ec2 delete-network-insights-path --network-insights-path-id "$NIP" > /dev/null
}

echo "--- 1. app -> db, porta 5432"; reach "$APP_ENI" "$DB_ENI" 5432
echo "--- 2. web -> db, porta 5432"; reach "$WEB_ENI" "$DB_ENI" 5432
echo "--- 3. app -> db, porta 22";   reach "$APP_ENI" "$DB_ENI" 22
# Esperado (a ordem das linhas "liberou"/"barrou" pode variar):
#
# --- 1. app -> db, porta 5432
# alcançável=true
#   liberou: insecurity-inc-checkout-app egress tcp 5432-5432 (referência: insecurity-inc-checkout-db)
#   liberou: insecurity-inc-checkout-db ingress tcp 5432-5432 (referência: insecurity-inc-checkout-app)
# --- 2. web -> db, porta 5432
# alcançável=false
#   barrou: egress em insecurity-inc-checkout-web (ENI_SG_RULES_MISMATCH)
#   barrou: ingress em insecurity-inc-checkout-db (ENI_SG_RULES_MISMATCH)
# --- 3. app -> db, porta 22
# alcançável=false
#   barrou: egress em insecurity-inc-checkout-app (ENI_SG_RULES_MISMATCH)
#   barrou: ingress em insecurity-inc-checkout-db (ENI_SG_RULES_MISMATCH)
```

O que o resultado ensina:

- **O fluxo legítimo passa por exatamente duas regras** — a saída da `app` (tcp 5432 → SG `db`) e a entrada do `db` (tcp 5432 ← SG `app`) —, as duas metades que a Correção, ponto 3, descreve. O JSON completo da análise traz também o caminho de **volta** (`ReturnPathComponents`) e ele não cita regra nenhuma: o security group é *stateful*, a resposta volta por conexão rastreada.
- **Os dois caminhos proibidos são barrados nas duas pontas**: cada um devolve duas explicações `ENI_SG_RULES_MISMATCH` ([códigos de explicação](https://docs.aws.amazon.com/vpc/latest/reachability/explanation-codes.html)) — uma de **saída**, no security group da origem, e uma de **entrada**, no do destino. São dois cadeados independentes. A porta 22, que o fundador abriu com um clique, agora esbarra em duas regras que nunca a citaram.
- **É a restrição de saída que dá o segundo cadeado.** Se a `web` tivesse a saída padrão "libera tudo", só a entrada do `db` a barraria — uma barreira em vez de duas, o anti-padrão de controlar só um dos lados (Problema, ponto 5).

### 🖥️ Repetindo os testes 1, 2 e opcional — Console (GUI)

**EC2** → **Security Groups** → selecione cada grupo → abas **Inbound rules** e **Outbound rules**: nas regras entre camadas, a coluna de origem/destino mostra o **ID de um security group** (`sg-...`), nunca um CIDR; o `default` da VPC do laboratório aparece com as duas abas vazias (passos 1 e 2). **EC2** → **Network Interfaces** → uma ENI → aba **Security groups** mostra o grupo associado. Para o teste opcional: **VPC** → **Reachability Analyzer** → **Create and analyze path** → em *Source type* e *Destination type*, **Network interfaces**; protocolo **TCP** e a porta de destino — o resultado detalha, componente a componente, quais regras liberaram ou barraram. Depois, apague o path (**Actions** → **Delete**); só a análise cobra, mas não deixe lixo.

## 🧹 Como destruir

### 🏗️ Terraform

```bash
terraform destroy
```

O Terraform respeita a ordem sozinho: as regras e as ENIs saem antes dos grupos (que não podem ser apagados enquanto algo os usa ou os referencia), depois a subnet e a VPC. Testado: `Destroy complete! Resources: 15 destroyed.` O `aws_default_security_group` não é "destruído" — o Terraform só deixa de gerenciá-lo, e ele vai embora junto com a VPC. Diferente da CMK do capítulo 06, nada aqui fica cobrando depois do destroy.

Depois do destroy (de qualquer um dos três caminhos), confira que não sobrou nada:

```bash
aws ec2 describe-vpcs --filters Name=tag:project,Values=insecurity-inc --query 'Vpcs[].VpcId' --output text
aws ec2 describe-security-groups --filters "Name=group-name,Values=insecurity-inc*" --query 'SecurityGroups[].GroupName' --output text
aws ec2 describe-network-interfaces --filters Name=tag:project,Values=insecurity-inc --query 'NetworkInterfaces[].NetworkInterfaceId' --output text
aws ec2 describe-network-insights-paths --query 'NetworkInsightsPaths[].NetworkInsightsPathId' --output text
# Esperado: as quatro saídas vazias
```

### ⌨️ AWS CLI

Aqui **a ordem importa**, e o motivo é o passo 6 de Como testar: dois security groups que se referenciam **não podem ser apagados**. O `web` cita a `app` (na saída) e a `app` cita a `web` (na entrada); o mesmo vale para `app` e `db` — e nenhum dos três sai primeiro. O Terraform resolve sozinho, apagando as regras (que são recursos) antes dos grupos; na CLI é por sua conta: as ENIs primeiro (um grupo em uso por uma ENI também não sai), depois revogar as duas regras de **entrada** que referenciam outro grupo, depois os grupos na ordem `web` → `app` → `db` e, por fim, a subnet e a VPC. Testado de ponta a ponta, em bash e zsh, na conta real.

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=insecurity-inc-lab Name=tag:chapter,Values=09 --query 'Vpcs[0].VpcId' --output text)
sg_id() { aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$1" --query 'SecurityGroups[0].GroupId' --output text; }
WEB_SG=$(sg_id insecurity-inc-checkout-web)
APP_SG=$(sg_id insecurity-inc-checkout-app)
DB_SG=$(sg_id insecurity-inc-checkout-db)
SUBNET_ID=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[0].SubnetId' --output text)
for v in VPC_ID WEB_SG APP_SG DB_SG SUBNET_ID; do eval "val=\$$v"; [ -n "$val" ] && [ "$val" != None ] || echo "$v VAZIA -- não continue sem corrigir (confira o login AWS; se já apagou tudo, não há mais nada a fazer)"; done

# 1. As três interfaces de rede -- um security group em uso por uma ENI não pode
#    ser apagado.
for name in web app db; do
  ENI=$(aws ec2 describe-network-interfaces --filters Name=vpc-id,Values="$VPC_ID" Name=tag:Name,Values="insecurity-inc-checkout-$name" --query 'NetworkInterfaces[0].NetworkInterfaceId' --output text)
  [ -n "$ENI" ] && [ "$ENI" != None ] || { echo "ENI $name VAZIA -- não achou; pulando"; continue; }
  aws ec2 delete-network-interface --network-interface-id "$ENI"
done

# 2. Desfaz o impasse dos grupos que se referenciam: o web referencia a app (na
#    saída) e a app referencia a web (na entrada), e o mesmo vale para app e db --
#    enquanto uma regra apontar para um grupo, ele não pode ser apagado (passo 6
#    de Como testar). Revogar as duas regras de ENTRADA que referenciam outro
#    grupo (app <- web e db <- app) basta.
for sg in "$APP_SG" "$DB_SG"; do
  RULE=$(aws ec2 describe-security-group-rules --filters Name=group-id,Values="$sg" --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' --output text)
  [ -n "$RULE" ] && [ "$RULE" != None ] || { echo "RULE de $sg VAZIA -- não achou regra de entrada; pulando"; continue; }
  aws ec2 revoke-security-group-ingress --group-id "$sg" --security-group-rule-ids "$RULE" > /dev/null
done

# 3. Os três security groups, NESTA ordem: o web já não é referenciado por
#    ninguém; ao sair, leva junto a regra que apontava para a app; e assim por
#    diante.
aws ec2 delete-security-group --group-id "$WEB_SG"
aws ec2 delete-security-group --group-id "$APP_SG"
aws ec2 delete-security-group --group-id "$DB_SG"

# 4. Subnet e VPC. Apagar a VPC leva junto o default security group, a network
#    ACL e a route table padrão.
aws ec2 delete-subnet --subnet-id "$SUBNET_ID"
aws ec2 delete-vpc --vpc-id "$VPC_ID"
```

Confira o resultado com o mesmo bloco de verificação da seção do Terraform, acima.

### 🖥️ Console (GUI)

1. **EC2** → **Network Interfaces** → selecione as três interfaces `insecurity-inc-checkout-*` → **Actions** → **Delete network interface**.
2. **EC2** → **Security Groups** → `insecurity-inc-checkout-app` → aba **Inbound rules** → **Edit inbound rules** → remova a regra → **Save rules**. Repita em `insecurity-inc-checkout-db`. (Sem isso, a exclusão dos grupos é recusada com `DependencyViolation` — ver a seção da CLI.)
3. Apague os grupos **nesta ordem** — `insecurity-inc-checkout-web`, depois `-app`, depois `-db`: selecione o grupo → **Actions** → **Delete security groups**.
4. **VPC** → **Your VPCs** → `insecurity-inc-lab` → **Actions** → **Delete VPC**. O console lista o que vai junto (subnet, network ACL, route table e o default security group); se ele pedir a subnet antes, apague-a em **VPC** → **Subnets**.
5. Se você rodou o teste opcional pelo Console: **VPC** → **Reachability Analyzer** → apague os paths que criou.

## 📚 Referências

- [SEC05-BP02 — Control traffic flow within your network layers](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_layered.html) — AWS Well-Architected Framework, Security Pillar; base do capítulo. Fonte dos anti-padrões citados (assumir que o tráfego dentro de uma camada é autorizado; controlar só a entrada ou só a saída) e da vantagem de citar outro security group pelo identificador.
- [Security group rules](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html) — só regras de permissão; regra de saída "libera tudo" em todo grupo novo; referência entre security groups (IPs privados, conta como uma regra, e o aviso de que a AWS não autoriza o IAM contra o grupo referenciado); caracteres permitidos nas descrições.
- [Default security groups for your VPCs](https://docs.aws.amazon.com/vpc/latest/userguide/default-security-group.html) — regras iniciais do `default`, o fato de não poder ser apagado (`Client.CannotDelete`) e de receber os recursos lançados sem grupo explícito.
- [Amazon EC2 security group connection tracking](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-connection-tracking.html) — a regra alterada não interrompe conexões rastreadas, a exceção das conexões não rastreadas (regra aberta nas duas direções) e a *network ACL* como forma de cortar na hora.
- [CIS AWS Foundations Benchmark in Security Hub CSPM](https://docs.aws.amazon.com/securityhub/latest/userguide/cis-aws-foundations-benchmark.html) — a tabela de mapeamento usada para a numeração: v5.0.0 (5.3, 5.4 e 5.5) e v3.0.0 (5.2, 5.3 e 5.4) → EC2.53, EC2.54 e EC2.2.
- [Security Hub CSPM controls for Amazon EC2](https://docs.aws.amazon.com/securityhub/latest/userguide/ec2-controls.html) — EC2.2, EC2.13, EC2.14, EC2.18 e EC2.19, com as regras do Config por trás de cada um.
- [restricted-ssh](https://docs.aws.amazon.com/config/latest/developerguide/restricted-ssh.html) e [vpc-default-security-group-closed](https://docs.aws.amazon.com/config/latest/developerguide/vpc-default-security-group-closed.html) — as regras gerenciadas do AWS Config que detectam, no capítulo 12, o que a consulta de auditoria do passo 0 faz à mão; [lista completa](https://docs.aws.amazon.com/config/latest/developerguide/managed-rules-by-aws-config.html) consultada para confirmar `restricted-common-ports` e `vpc-sg-open-only-to-authorized-ports`.
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) — acesso a instâncias sem portas de entrada abertas, sem bastion e sem chaves SSH, controlado por IAM; a ressalva sobre sessões via *port forwarding* ou SSH.
- [Default VPCs](https://docs.aws.amazon.com/vpc/latest/userguide/default-vpc.html) — a VPC padrão vem com uma subnet pública por zona e um internet gateway (conferido nesta conta, no Problema, ponto 1).
- [Amazon VPC — pricing](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html#pricing) e [Amazon VPC Pricing](https://aws.amazon.com/vpc/pricing/) — a VPC em si não tem cobrança adicional; o Reachability Analyzer custa US$0,10 por análise processada (base da nota de custo do teste opcional).
- [What is Reachability Analyzer?](https://docs.aws.amazon.com/vpc/latest/reachability/what-is-reachability-analyzer.html) e [Reachability Analyzer explanation codes](https://docs.aws.amazon.com/vpc/latest/reachability/explanation-codes.html) — o motor de análise do teste opcional e o significado do `ENI_SG_RULES_MISMATCH`.
- Terraform AWS provider: [`aws_security_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) (remoção da regra de saída padrão, `description`/`name`/`vpc_id` forçando recriação, aviso contra misturar regras inline e standalone), [`aws_vpc_security_group_ingress_rule`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) e [`aws_default_security_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) — este último, com a ressalva descoberta no teste: sem `ingress = []` e `egress = []` explícitos, ele só esvazia o grupo na adoção e não detecta regras criadas depois.
