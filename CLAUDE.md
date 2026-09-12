# CLAUDE.md

Contexto para qualquer sessão do Claude Code trabalhando neste repositório.

## Sobre o projeto

Portfólio de boas práticas de segurança AWS, estruturado como sátira: **Insecurity Inc.**, uma empresa fictícia que acabou de abrir uma conta AWS e precisa corrigir uma sequência de más práticas de segurança até atingir maturidade.

A sátira é **só a casca** (nomes, narrativa, README). O conteúdo técnico por baixo (Terraform, políticas IAM, referências ao CIS AWS Foundations Benchmark e ao AWS Well-Architected Security Pillar) precisa ser rigoroso e correto — não é uma piada solta, é um projeto técnico sério com uma moldura leve.

Repositório: https://github.com/smartao/insecurity-inc

## Restrição de custo (importante)

A conta AWS usada **não tem mais free tier**. Regras:

- Sempre `terraform destroy` ao final de cada capítulo, antes de começar o próximo.
- Cuidado especial com:
  - **KMS** (cap. 06): CMK cobra ~$1/mês/chave (prorrateado ao dia). Deleção tem janela mínima de 7 dias ainda sendo cobrada.
  - **AWS Config** (cap. 12): cobra por item de configuração gravado + avaliação de regra, sem free tier perene. É o serviço com maior risco de custo esquecido — nunca deixar o recorder ligado sem necessidade.
  - **Secrets Manager** (cap. 08): ~$0.40/mês/secret.
- Capítulo 00 existe justamente para ter billing alarm/budget configurado antes de qualquer outro laboratório.

## Estrutura de contas AWS

Já existe uma AWS Organization com uma única conta isolada. Decisão: manter conta única para os capítulos 00–13. Multi-conta (via OU) só entra nos capítulos 14–15 (SCP/RCP), como arco de "maturidade organizacional" — não é necessário para o resto do projeto.

## Roadmap de capítulos

17 capítulos (00–16). 🟢 = grátis/quase grátis, 🟡 = custo mensal real e baixo.

| # | Arco | Capítulo | Conceito | Custo | Depende de |
|---|------|----------|----------|-------|------------|
| 00 | Fundação | Billing Alarm & Budgets | Safety net | 🟢 | — |
| 01 | Identidade | IAM Least Privilege | Policy estática (RBAC) | 🟢 | — |
| 02 | Identidade | ABAC | Policy dinâmica por tags | 🟢 | 01 |
| 03 | Identidade | IAM Access Analyzer | Acesso externo não intencional | 🟢 | — |
| 04 | Identidade | MFA Enforcement | Condição de política exigindo MFA | 🟢 | — |
| 05 | Dados | S3 Security | Bucket Policy / Public Access Block | 🟢 | — |
| 06 | Dados | KMS | Encryption + Key Policy | 🟡 | — |
| 07 | Dados | Parameter Store | Config segura | 🟢 | — |
| 08 | Dados | Secrets Manager | Secrets rotacionados | 🟡 | — |
| 09 | Rede | Security Groups | Regras de rede | 🟢 | — |
| 10 | Rede | VPC Flow Logs | Visibilidade de tráfego | 🟢 | — |
| 11 | Detecção & Auditoria | CloudTrail | Auditoria de API | 🟢 | — |
| 12 | Detecção & Auditoria | AWS Config | Compliance contínuo | 🟡 | — |
| 13 | Detecção & Auditoria | EventBridge | Detecção baseada em eventos | 🟢 | 12 |
| 14 | Governança (Org) | Organizations + SCP | Guardrail do lado da identidade | 🟢 | — |
| 15 | Governança (Org) | Organizations + RCP | Guardrail do lado do recurso | 🟢 | Reaproveita 05, 06 |
| 16 | Fechamento | Well-Architected Review | Auditoria final | 🟢 | Todos anteriores |

## Convenções

- **Tags**: definir e aplicar consistentemente desde o capítulo 00/01 (ex.: `project=insecurity-inc`, `env=lab`, `chapter=NN`) — o capítulo 02 (ABAC) depende de tagging consistente nos recursos anteriores.
- **RCP (cap. 15)**: feature recente da AWS (lançada no final de 2024), cobertura de serviços ainda limitada (S3, KMS, STS, IAM roles, SQS, Secrets Manager, DynamoDB). Conferir documentação oficial atualizada antes de implementar.
- **Narrativa**: cada capítulo conta uma etapa da jornada de maturidade da Insecurity Inc. — tem um "antes" (prática ruim) e um "depois" (correção), não é só um checklist técnico.

## Estrutura de pastas

Ainda não definida — próximo passo do projeto.
