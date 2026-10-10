terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.5.0: versão em que o provider adicionou recording_strategy /
      # resource_types independentes de all_supported ao
      # aws_config_configuration_recorder (ver README, Correção, ponto 1).
      version = "~> 5.5"
    }
  }
}

provider "aws" {
  region = var.region
}
