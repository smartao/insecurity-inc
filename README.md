# insecurity-inc

![Insecurity Inc. — "Same Business. Less Security." Quadrinho satírico de um escritório de tech: CEO comemorando "more features, less security" enquanto a equipe entra em pânico ao lado de um quadro branco listando más práticas de segurança na AWS (S3 público, Security Group 0.0.0.0/0, root user em uso, sem MFA, chaves no código, CloudTrail desabilitado, sem backup, sem monitoramento) prestes a ir para produção.](./imagens/insecurity-inc-capa-02-13092026.png)

> A Insecurity Inc. acabou de abrir uma conta AWS. Este repositório documenta a jornada de correção das más práticas de segurança até atingir maturidade — cada capítulo é um cenário aplicável em Terraform.

Detalhes de contexto, restrições de custo e decisões de arquitetura estão em [CLAUDE.md](./CLAUDE.md).

## Capítulos

| # | Arco | Capítulo | Custo |
|---|------|----------|-------|
| [00](./00-billing-alarm) | Fundação | Billing Alarm & Budgets | 🟢 |
| [01](./01-iam-least-privilege) | Identidade | IAM Least Privilege | 🟢 |
| [02](./02-abac) | Identidade | ABAC | 🟢 |
| [03](./03-iam-access-analyzer) | Identidade | IAM Access Analyzer | 🟢 |
| [04](./04-mfa-enforcement) | Identidade | MFA Enforcement | 🟢 |
| [05](./05-s3-security) | Dados | S3 Security | 🟢 |
| [06](./06-kms) | Dados | KMS | 🟡 |
| [07](./07-parameter-store) | Dados | Parameter Store | 🟢 |
| [08](./08-secrets-manager) | Dados | Secrets Manager | 🟡 |
| [09](./09-security-groups) | Rede | Security Groups | 🟢 |
| [10](./10-vpc-flow-logs) | Rede | VPC Flow Logs | 🟢 |
| [11](./11-cloudtrail) | Detecção & Auditoria | CloudTrail | 🟢 |
| [12](./12-aws-config) | Detecção & Auditoria | AWS Config | 🟡 |
| [13](./13-eventbridge) | Detecção & Auditoria | EventBridge | 🟢 |
| [14](./14-organizations-scp) | Governança (Org) | Organizations + SCP | 🟢 |
| [15](./15-organizations-rcp) | Governança (Org) | Organizations + RCP | 🟢 |
| [16](./16-well-architected-review) | Fechamento | Well-Architected Review | 🟢 |

## Aviso de custo

A conta AWS usada não tem free tier. Sempre rode `terraform destroy` ao final de cada capítulo antes de seguir para o próximo — veja detalhes em [CLAUDE.md](./CLAUDE.md#restrição-de-custo-importante).

## Licença

[MIT](./LICENSE)
