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

data "archive_file" "lambda_init" {
  type = "zip"
  source_dir = "lambdas/src/init"
  output_path = "lambdas/dist/init.zip"
}

resource "aws_iam_role" "lambda_init" {
  name = "lambda_init"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
