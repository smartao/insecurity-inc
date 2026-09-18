# Mapeamento — AWS Well-Architected Framework, Security Pillar

Referência de todas as best practices (BPs) do pilar de segurança do AWS
Well-Architected Framework, cruzadas com o que o projeto **Insecurity Inc.**
já cita explicitamente (linha `**Well-Architected:**` no cabeçalho de cada
capítulo, mais referências adicionais no corpo/seção "Referências" dos
READMEs).

A estrutura oficial tem **7 áreas**, **11 perguntas (SEC01–SEC11)** e **63
best practices**. Hoje o repositório cita **15 de 63** BPs, distribuídas em
6 das 11 perguntas. O capítulo 16 (Well-Architected Review) faz uma revisão
geral do pilar inteiro e não tem BP específico associado.

> Atualizar esta tabela sempre que um novo capítulo citar uma BP nova, ou
> quando uma BP existente ganhar uma citação adicional em outro capítulo.
>
> Roadmap completo da série (Temporada 1 + plano das Temporadas 2 e 3):
> [`roadmap-temporadas.md`](./roadmap-temporadas.md).

## 1. Security foundations (SEC01) — 0/8 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC01-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_multi_accounts.html) | Separate workloads using accounts | Isolar ambientes/workloads em contas AWS separadas como boundary primário de segurança | ⬜ Disponível |
| [SEC01-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_aws_account.html) | Secure account root user and properties | Proteger o root user (MFA, credenciais não usadas no dia a dia, regra de dois responsáveis) | ⬜ Disponível |
| [SEC01-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_control_objectives.html) | Identify and validate control objectives | Definir objetivos de controle de segurança alinhados a requisitos regulatórios/organizacionais | ⬜ Disponível |
| [SEC01-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_updated_threats.html) | Stay up to date with security threats and recommendations | Acompanhar continuamente novas ameaças e recomendações (AWS Security Bulletins, feeds de inteligência) | ⬜ Disponível |
| [SEC01-BP05](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_reduce_management_scope.html) | Reduce security management scope | Usar serviços gerenciados/serverless para reduzir a superfície que você precisa proteger diretamente | ⬜ Disponível |
| [SEC01-BP06](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_automate_security_controls.html) | Automate deployment of standard security controls | Automatizar (IaC) a aplicação de controles de segurança padrão em novos recursos/contas | ⬜ Disponível |
| [SEC01-BP07](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_threat_model.html) | Identify threats and prioritize mitigations using a threat model | Manter um threat model vivo para priorizar onde investir mitigação | ⬜ Disponível |
| [SEC01-BP08](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_securely_operate_implement_services_features.html) | Evaluate and implement new security services and features regularly | Revisar periodicamente novos serviços/features de segurança lançados pela AWS | ⬜ Disponível |

> Os capítulos 14/15 (Organizations, SCP/RCP) tocam indiretamente em
> SEC01-BP01 (separação de contas), mas o repo cita SEC03-BP05 como BP
> primário desses capítulos — SEC01 continua sem citação própria.

## 2. Identity management (SEC02) — 3/6 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC02-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_enforce_mechanisms.html) | Use strong sign-in mechanisms | Exigir MFA e políticas de senha fortes para reduzir risco de credencial comprometida | ✅ Cap. 04 (MFA Enforcement) |
| [SEC02-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_unique.html) | Use temporary credentials | Preferir credenciais temporárias (roles/STS) a chaves de acesso de longa duração | ⬜ Disponível |
| [SEC02-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_secrets.html) | Store and use secrets securely | Armazenar segredos em serviço dedicado com rotação, em vez de hardcoded/plaintext | ✅ Cap. 08 (Secrets Manager) |
| [SEC02-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_identity_provider.html) | Rely on a centralized identity provider | Centralizar identidades humanas via IdP (SSO/IAM Identity Center) em vez de usuários IAM locais | ⬜ Disponível |
| [SEC02-BP05](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_audit.html) | Audit and rotate credentials periodically | Auditar e rotacionar periodicamente credenciais de longa duração que ainda existirem | ⬜ Disponível |
| [SEC02-BP06](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_groups_attributes.html) | Employ user groups and attributes | Gerenciar permissões por grupo/atributo (tags) em vez de por usuário individual | ✅ Cap. 02 (ABAC) |

## 3. Permissions management (SEC03) — 4/9 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC03-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_define.html) | Define access requirements | Definir explicitamente quem/o que precisa acessar cada recurso, antes de conceder permissão | ⬜ Disponível |
| [SEC03-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_least_privileges.html) | Grant least privilege access | Conceder apenas as permissões mínimas necessárias para a tarefa | ✅ Cap. 01 (IAM Least Privilege), citado também no Cap. 02 |
| [SEC03-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_emergency_process.html) | Establish emergency access process | Ter um processo de "break glass" para acesso emergencial fora do fluxo normal | ⬜ Disponível |
| [SEC03-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_continuous_reduction.html) | Reduce permissions continuously | Revisar e podar continuamente permissões não usadas (ex.: via IAM Access Analyzer policy generation) | ⬜ Disponível |
| [SEC03-BP05](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_define_guardrails.html) | Define permission guardrails for your organization | Guardrails no nível de organização (SCP/RCP) que limitam o teto de permissão de todas as contas | ✅ Cap. 14 (SCP), Cap. 15 (RCP, por analogia) |
| [SEC03-BP06](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_lifecycle.html) | Manage access based on lifecycle | Provisionar/desprovisionar acesso automaticamente conforme o ciclo de vida (onboarding/offboarding) | ⬜ Disponível |
| [SEC03-BP07](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_analyze_cross_account.html) | Analyze public and cross-account access | Detectar continuamente acesso público/cross-account não intencional | ✅ Cap. 03 (IAM Access Analyzer) |
| [SEC03-BP08](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_share_securely.html) | Share resources securely within your organization | Compartilhar recursos entre contas da própria organização de forma segura (ex.: RAM) | ⬜ Disponível |
| [SEC03-BP09](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_share_securely_third_party.html) | Share resources securely with a third party | Mitigar confused deputy em acesso de terceiros (ex.: External ID único) | ✅ Cap. 03 (External ID, citado no corpo) |

## 4. Detection (SEC04) — 3/4 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC04-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_detect_investigate_events_app_service_logging.html) | Configure service and application logging | Habilitar logging nos serviços/aplicações como base de qualquer detecção | ✅ Cap. 10 (VPC Flow Logs), Cap. 11 (CloudTrail) |
| [SEC04-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_detect_investigate_events_logs.html) | Capture logs, findings, and metrics in standardized locations | Centralizar logs/findings/métricas em locais padronizados para análise | ⬜ Disponível |
| [SEC04-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_detect_investigate_events_security_alerts.html) | Correlate and enrich security alerts | Correlacionar e enriquecer alertas para reduzir ruído e priorizar investigação | ✅ Cap. 00 (Billing Alarm), Cap. 13 (EventBridge) |
| [SEC04-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_detect_investigate_events_noncompliant_resources.html) | Initiate remediation for non-compliant resources | Acionar remediação (manual ou automática) quando um recurso sai de compliance | ✅ Cap. 12 (AWS Config) |

## 5. Protecting networks (SEC05) — 1/4 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC05-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_create_layers.html) | Create network layers | Segmentar a rede em camadas (subnets públicas/privadas, VPCs) por sensibilidade | ⬜ Disponível |
| [SEC05-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_layered.html) | Control traffic flow within your network layers | Controlar o tráfego entre camadas com regras explícitas (SG/NACL) em vez de acesso amplo | ✅ Cap. 09 (Security Groups) |
| [SEC05-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_protection_inspection.html) | Implement inspection-based protection | Inspecionar tráfego (WAF, Network Firewall, IDS/IPS) além de apenas permitir/negar por porta | ⬜ Disponível |
| [SEC05-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_network_auto_protect.html) | Automate network protection | Automatizar a aplicação/remediação de controles de rede via IaC/pipelines | ⬜ Disponível |

## 6. Protecting compute (SEC06) — 0/5 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC06-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_compute_vulnerability_management.html) | Perform vulnerability management | Escanear e corrigir vulnerabilidades continuamente (ex.: Amazon Inspector) | ⬜ Disponível |
| [SEC06-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_compute_hardened_images.html) | Provision compute from hardened images | Provisionar compute a partir de imagens/templates já hardened | ⬜ Disponível |
| [SEC06-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_compute_reduce_manual_management.html) | Reduce manual management and interactive access | Reduzir SSH/acesso interativo manual em favor de automação (ex.: SSM Session Manager) | ⬜ Disponível |
| [SEC06-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_compute_validate_software_integrity.html) | Validate software integrity | Validar integridade/proveniência de software (assinatura, checksums) antes de rodar | ⬜ Disponível |
| [SEC06-BP05](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_compute_auto_protection.html) | Automate compute protection | Automatizar a proteção de compute (patch, config baseline) via pipelines | ⬜ Disponível |

> Nenhum capítulo do roadmap 00–16 provisiona compute (EC2/ECS/Lambda)
> diretamente — por isso SEC06 fica inteiramente fora do escopo atual.

## 7. Data classification (SEC07) — 0/4 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC07-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_data_classification_identify_data.html) | Understand your data classification scheme | Definir um esquema de classificação (ex.: público/interno/confidencial) para os dados | ⬜ Disponível |
| [SEC07-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_data_classification_define_protection.html) | Apply data protection controls based on data sensitivity | Aplicar controles de proteção proporcionais à sensibilidade de cada classe de dado | ⬜ Disponível |
| [SEC07-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_data_classification_auto_classification.html) | Automate identification and classification | Automatizar a identificação/classificação de dados sensíveis (ex.: Macie) | ⬜ Disponível |
| [SEC07-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_data_classification_lifecycle_management.html) | Define scalable data lifecycle management | Definir ciclo de vida do dado (retenção, expiração) de forma escalável | ⬜ Disponível |

## 8. Protecting data at rest (SEC08) — 3/4 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC08-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_key_mgmt.html) | Implement secure key management | Gerenciar chaves de criptografia com key policy própria, separada do IAM | ✅ Cap. 06 (KMS) |
| [SEC08-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_encrypt.html) | Enforce encryption at rest | Exigir criptografia em repouso por padrão nos serviços de armazenamento | ✅ Cap. 07 (Parameter Store) |
| [SEC08-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_automate_protection.html) | Automate data at rest protection | Automatizar a aplicação/verificação de proteção de dados em repouso (ex.: Config rules) | ⬜ Disponível |
| [SEC08-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_rest_access_control.html) | Enforce access control | Restringir e revisar regularmente quem pode acessar cada dado armazenado | ✅ Cap. 05 (S3 Security) |

## 9. Protecting data in transit (SEC09) — 1/3 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC09-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_transit_key_cert_mgmt.html) | Implement secure key and certificate management | Gerenciar certificados/chaves usados para proteger dados em trânsito (ex.: ACM) | ⬜ Disponível |
| [SEC09-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_transit_encrypt.html) | Enforce encryption in transit | Exigir TLS/transporte seguro, negando explicitamente conexões inseguras | ✅ Cap. 05 (S3 `DenyInsecureTransport`) |
| [SEC09-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_protect_data_transit_authentication.html) | Authenticate network communications | Autenticar as duas pontas da comunicação de rede, não só criptografar | ⬜ Disponível |

## 10. Incident response (SEC10) — 0/8 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC10-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_identify_personnel.html) | Identify key personnel and external resources | Mapear com antecedência quem aciona/participa de um incidente | ⬜ Disponível |
| [SEC10-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_develop_management_plans.html) | Develop incident management plans | Documentar planos formais de gestão de incidente | ⬜ Disponível |
| [SEC10-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_prepare_forensic.html) | Prepare forensic capabilities | Preparar capacidade forense (snapshots, isolamento) antes de precisar dela | ⬜ Disponível |
| [SEC10-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_playbooks.html) | Develop and test security incident response playbooks | Criar e testar playbooks por tipo de incidente | ⬜ Disponível |
| [SEC10-BP05](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_pre_provision_access.html) | Pre-provision access | Ter roles/acesso de emergência pré-provisionados para o time de resposta | ⬜ Disponível |
| [SEC10-BP06](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_pre_deploy_tools.html) | Pre-deploy tools | Ter ferramental de resposta pré-implantado, pronto para uso | ⬜ Disponível |
| [SEC10-BP07](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_run_game_days.html) | Run simulations | Rodar simulações (game days) para testar o processo de resposta | ⬜ Disponível |
| [SEC10-BP08](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_incident_response_establish_incident_framework.html) | Establish a framework for learning from incidents | Ter um framework de post-mortem para aprender com cada incidente | ⬜ Disponível |

> O Cap. 13 (EventBridge) fica em SEC04 (detecção), não em SEC10 — o
> roadmap não inclui um capítulo de resposta a incidente propriamente dito.

## 11. Application security (SEC11) — 0/8 usados

| BP | Título | Resumo | Status |
|---|---|---|---|
| [SEC11-BP01](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_train_for_application_security.html) | Train for application security | Treinar builders em segurança de aplicação | ⬜ Disponível |
| [SEC11-BP02](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_automate_testing_throughout_lifecycle.html) | Automate testing throughout the development and release lifecycle | Automatizar testes de segurança ao longo do SDLC | ⬜ Disponível |
| [SEC11-BP03](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_perform_regular_penetration_testing.html) | Perform regular penetration testing | Realizar pentest regularmente | ⬜ Disponível |
| [SEC11-BP04](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_manual_code_reviews.html) | Conduct code reviews | Fazer revisão de código com foco em segurança | ⬜ Disponível |
| [SEC11-BP05](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_centralize_services_for_packages_and_dependencies.html) | Centralize services for packages and dependencies | Centralizar repositórios de pacotes/dependências | ⬜ Disponível |
| [SEC11-BP06](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_deploy_software_programmatically.html) | Deploy software programmatically | Fazer deploy só via automação, nunca manualmente | ⬜ Disponível |
| [SEC11-BP07](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_regularly_assess_security_properties_of_pipelines.html) | Regularly assess security properties of the pipelines | Avaliar regularmente a segurança do próprio pipeline de CI/CD | ⬜ Disponível |
| [SEC11-BP08](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_appsec_build_program_that_embeds_security_ownership_in_teams.html) | Build a program that embeds security ownership in workload teams | Criar programa que dá ownership de segurança aos próprios times de workload | ⬜ Disponível |

> Esse arco é sobre segurança de código de aplicação/SDLC — fora do escopo
> do projeto (infra AWS via Terraform, sem app code).

---

## Onde o repo já pisou fundo vs. onde não chegou

- **Cobertos com múltiplas citações**: SEC03 (permissões) e SEC04
  (detecção) — 4/9 e 3/4 respectivamente.
- **Cobertos parcialmente**: SEC02, SEC05, SEC08, SEC09 — cada um com 1 a 3
  BPs citados de um total pequeno.
- **Zero cobertura**: SEC01 (foundations), SEC06 (compute), SEC07
  (classificação de dado), SEC10 (resposta a incidente), SEC11 (appsec) —
  coerente com o roadmap atual, que é infra/IAM/dados/rede/detecção, sem
  capítulo de compute, classificação de dado ou resposta a incidente.

## Referências

- [AWS Well-Architected Framework — Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
