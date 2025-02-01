terraform {
  required_version = "~> 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.84.0"
    }
  }

  backend "s3" {
    bucket         = "berbbobs-minecraft-tfstate"
    key            = "mcraft/state/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "minecraft_tf_lockid"
  }
}

provider "aws" {
  region = "eu-west-1"
}