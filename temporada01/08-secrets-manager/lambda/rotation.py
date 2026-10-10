"""Rotation Lambda do secret de credenciais do banco do checkout (capítulo 08).

Implementa o protocolo de rotação do Secrets Manager, em quatro etapas
chamadas em sequência pelo próprio serviço (createSecret -> setSecret ->
testSecret -> finishSecret), usando os staging labels AWSPENDING / AWSCURRENT /
AWSPREVIOUS para nunca deixar o secret sem uma versão válida no meio do caminho.

LIMITAÇÃO DELIBERADA DO LABORATÓRIO: não existe banco de dados de verdade neste
capítulo (um RDS quebraria a restrição de custo do projeto e exigiria VPC, que
só entra no arco de Rede, cap. 09). Por isso setSecret e testSecret NÃO trocam
nem testam a senha em banco nenhum -- só validam o formato e registram que
fariam isso. As etapas createSecret e finishSecret são reais: geram a senha
nova, gravam a versão e movem o label AWSCURRENT. Num banco real, é o setSecret
que faz a senha antiga (a que o funcionário que saiu ainda conhece) deixar de
funcionar; ver README, seção Correção.

Nunca logue o valor do secret: o que vai para o CloudWatch Logs aqui são só
ARN, etapa e id de versão.
"""

import json
import logging

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Caracteres que quebrariam quoting de shell ou de string de conexão.
EXCLUDE_CHARACTERS = "/@\"'\\`$"
PASSWORD_LENGTH = 24

# Formato compatível com os templates oficiais de rotação de banco da AWS,
# para o dia em que este lab ganhar um banco de verdade.
REQUIRED_KEYS = ("username", "password", "host")


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    client = boto3.client("secretsmanager")

    metadata = client.describe_secret(SecretId=arn)
    if not metadata.get("RotationEnabled"):
        raise ValueError(f"Rotação não está habilitada para o secret {arn}")

    stages = metadata["VersionIdsToStages"]
    if token not in stages:
        raise ValueError(f"A versão {token} não tem nenhum stage no secret {arn}")
    if "AWSCURRENT" in stages[token]:
        # Chamada repetida para uma rotação que já terminou: idempotência.
        logger.info("Versão %s já é AWSCURRENT em %s -- nada a fazer.", token, arn)
        return
    if "AWSPENDING" not in stages[token]:
        raise ValueError(f"A versão {token} não está como AWSPENDING no secret {arn}")

    steps = {
        "createSecret": create_secret,
        "setSecret": set_secret,
        "testSecret": test_secret,
        "finishSecret": finish_secret,
    }
    if step not in steps:
        raise ValueError(f"Step inválido: {step}")

    steps[step](client, arn, token)


def get_secret_dict(client, arn, stage, token=None):
    kwargs = {"SecretId": arn, "VersionStage": stage}
    if token:
        kwargs["VersionId"] = token
    return json.loads(client.get_secret_value(**kwargs)["SecretString"])


def create_secret(client, arn, token):
    current = get_secret_dict(client, arn, "AWSCURRENT")

    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        # Guardar o valor novo em AWSPENDING é o que torna a etapa idempotente:
        # se a rotação falhar adiante e o serviço tentar de novo, reaproveita.
        logger.info("createSecret: a versão %s já tem valor em AWSPENDING -- reaproveitando.", token)
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    pending = dict(current)
    pending["password"] = client.get_random_password(
        PasswordLength=PASSWORD_LENGTH,
        ExcludeCharacters=EXCLUDE_CHARACTERS,
    )["RandomPassword"]

    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(pending),
        VersionStages=["AWSPENDING"],
    )
    logger.info("createSecret: nova versão %s gravada como AWSPENDING em %s.", token, arn)


def set_secret(client, arn, token):
    current = get_secret_dict(client, arn, "AWSCURRENT")
    pending = get_secret_dict(client, arn, "AWSPENDING", token)

    # Guarda contra "confused deputy" (recomendação da documentação oficial):
    # esta função tem poder de alterar credencial no destino, então só age se
    # AWSCURRENT e AWSPENDING apontam para o MESMO usuário no MESMO host.
    for key in ("username", "host"):
        if current.get(key) != pending.get(key):
            raise ValueError(f"setSecret: '{key}' difere entre AWSCURRENT e AWSPENDING -- rotação abortada.")

    # STUB: num banco real, aqui entraria algo como
    #   ALTER USER <username> WITH PASSWORD '<pending password>'
    # (com query parametrizada), e a senha antiga passaria a ser rejeitada.
    logger.info("setSecret: (stub, sem banco neste lab) trocaria a senha de '%s' em '%s'.",
                pending["username"], pending["host"])


def test_secret(client, arn, token):
    pending = get_secret_dict(client, arn, "AWSPENDING", token)

    missing = [key for key in REQUIRED_KEYS if not pending.get(key)]
    if missing:
        raise ValueError(f"testSecret: AWSPENDING sem os campos obrigatórios: {', '.join(missing)}")

    # STUB: num banco real, aqui a Lambda abriria uma conexão com a senha nova
    # e rodaria uma consulta de leitura; falhar aqui aborta a rotação ANTES de
    # a versão nova virar AWSCURRENT, então a aplicação nunca vê uma senha ruim.
    logger.info("testSecret: (stub, sem banco neste lab) formato de AWSPENDING validado.")


def finish_secret(client, arn, token):
    metadata = client.describe_secret(SecretId=arn)

    current_version = None
    for version, stages in metadata["VersionIdsToStages"].items():
        if "AWSCURRENT" in stages:
            if version == token:
                logger.info("finishSecret: a versão %s já é AWSCURRENT.", version)
                return
            current_version = version
            break

    # Uma única chamada move AWSCURRENT para a versão nova; o serviço marca a
    # antiga como AWSPREVIOUS (último valor bom conhecido). O AWSPENDING pode
    # continuar preso à versão nova, que agora também é AWSCURRENT -- observado
    # neste lab e previsto na documentação da AWS, e inofensivo: só sinaliza
    # rotação incompleta quando fica numa versão DIFERENTE da AWSCURRENT.
    # Não removê-lo por conta própria, em chamada separada.
    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info("finishSecret: AWSCURRENT movido da versão %s para %s em %s.", current_version, token, arn)
