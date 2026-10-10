terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 5.77 foi a primeira versão do provider a aceitar
      # type = "RESOURCE_CONTROL_POLICY" em aws_organizations_policy
      # (RCP foi lançada em novembro de 2024).
      version = "~> 5.77"
    }
  }
}

provider "aws" {
  region = var.region
}
