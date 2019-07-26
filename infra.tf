locals {
  org = "luotaoruby"
  aws_region = "us-west-2"
  aws_creds_file_path = "~/.aws/credentials"
  aws_profile_name = "default"

  lambda_worker_memory = 2048
  lambda_worker_timeout = 30
}

provider "aws" {
  region = "${local.aws_region}"
  shared_credentials_file = "${local.aws_creds_file_path}"
  profile = "${local.aws_profile_name}"
}
