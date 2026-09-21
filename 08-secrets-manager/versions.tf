terraform {
  # 1.11+: atributos write-only (secret_string_wo) e recursos efêmeros
  # (ephemeral "random_password"), que mantêm a senha inicial fora do state.
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 5.100 é o mínimo testado com secret_string_wo.
      version = "~> 5.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}
