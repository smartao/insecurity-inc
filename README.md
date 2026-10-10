# 🔓 insecurity-inc

![Insecurity Inc. — "Same Business. Less Security." Quadrinho satírico de um escritório de tech: CEO comemorando "more features, less security" enquanto a equipe entra em pânico ao lado de um quadro branco listando más práticas de segurança na AWS (S3 público, Security Group 0.0.0.0/0, root user em uso, sem MFA, chaves no código, CloudTrail desabilitado, sem backup, sem monitoramento) prestes a ir para produção.](./imagens/insecurity-inc-capa-02-13092026.jpg)

> A Insecurity Inc. acabou de abrir uma conta AWS. Este repositório documenta a jornada de correção das más práticas de segurança até atingir maturidade — cada capítulo é um cenário aplicável em Terraform.

Detalhes de contexto, restrições de custo e decisões de arquitetura estão em [CLAUDE.md](./CLAUDE.md).

## 🗂️ Temporada 1 — Do Zero à Primeira Auditoria

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

### 🏁 Fim da Temporada 1

![Insecurity Inc. — fim da Temporada 1. O time em clima de comemoração: o CEO de óculos escuros ergue a caneca "Still insecure but learning" enquanto os outros olham para uma lousa intitulada "Nossa Jornada na AWS Security", com os capítulos 00 a 16 ligados por setas, de Billing Alarm a Well-Architected Review, e um post-it "17 — What's Next?" para onde o arquiteto aponta. Nas paredes, os recados "Security is a journey... not a checkbox" e "Mesmas pessoas. Novas perspectivas. Mais segurança (esperamos)."; na mesa, livros de compliance, governança e risco, uma pizza e a lista "Next Steps: mais maturidade, menos surpresas, mais valor, Insecurity Inc. continua...".](./imagens/cover-S01E17.jpg)

Do capítulo 00 ao 16, a Insecurity Inc. saiu de uma conta AWS sem nem um alarme de gasto para uma organização com guardrails de identidade (SCP) e de recurso (RCP), trilha de auditoria, compliance contínuo e a primeira revisão formal do pilar de segurança.

Essa mesma revisão, no [capítulo 16](./16-well-architected-review), mostra o tamanho do caminho que falta: 16 das 63 práticas atendidas e 9 das 11 perguntas ainda com risco alto. A caneca do CEO resume bem: *still insecure, but learning*.

**What's next?** As lacunas que pedem capítulo próprio (tirar os workloads da management account, deploy por pipeline sem access key estática, VPC em camadas, plano de resposta a incidente) estão no [Plano de melhoria](./16-well-architected-review/README.md#-plano-de-melhoria) do capítulo 16. Elas são o ponto de partida da Temporada 2, em planejamento.

## 💸 Aviso de custo

A conta AWS usada não tem free tier. Sempre rode `terraform destroy` ao final de cada capítulo antes de seguir para o próximo — veja detalhes em [CLAUDE.md](./CLAUDE.md#restrição-de-custo-importante).

## 📄 Licença

[Apache License 2.0](./LICENSE)
