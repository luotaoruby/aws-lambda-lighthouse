locals {
  app_version           = "0.0.1"
  org                   = "ryo"
  aws_region            = "us-west-2"
  aws_creds_file_path   = "~/.aws/credentials"
  aws_profile_name      = "default"
  lambda_worker_memory  = 2048
  lambda_worker_timeout = 30
}

provider "aws" {
  region                  = "${local.aws_region}"
  shared_credentials_file = "${local.aws_creds_file_path}"
  profile                 = "${local.aws_profile_name}"
}

# S3 bucket
resource "aws_s3_bucket" "lighthouse_metrics" {
  bucket = "${local.org}-lighthouse-metrics"
  acl    = "private"
}

# DynamoDB
resource "aws_dynamodb_table" "lighthouse_metrics_entries" {
  name         = "LighthouseMetricsEntries"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "EntryId"
  attribute {
    name = "EntryId"
    type = "S"
  }
}

resource "aws_dynamodb_table" "lighthouse_metrics_jobs" {
  name             = "LighthouseMetricsJobs"
  billing_mode     = "PAY_PER_REQUEST"
  has_key          = "JobId"
  attribute {
    name = "JobId"
    type = "S"
  }
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"
}

resource "aws_dynamodb_table" "lighthouse_metrics_runs" {
  name         = "LighthouseMetricsRuns"
  billing_mode = "PAY_PER_REQUEST"
  has_key      = "RunId"
  global_secondary_index {
    name            = "JobIdIndex"
    hash_key        = "JobId"
    projection_type = "KEYS_ONLY"
  }
  global_secondary_index {
    name            = "EntryIdIndex"
    hash_key        = "EntryId"
    projection_type = "KEYS_ONLY"
  }
  attribute {
    name = "RunId"
    type = "S"
  }
  attribute {
    name = "RunId"
    type = "S"
  }
  attribute {
    name = "JobId"
    type = "S"
  }
}

# SNS
resource "aws_sns_topic" "pages_to_test" {
  name = "lighthouse-pages-to-test"
}

resource "aws_sns_topic" "pages_to_test_dlq" {
  name = "lighthouse-pages-to-test-dlq"
}


resource "aws_iam_role" "lambda_graph" {
  name               = "lambda_graph"
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

resource "aws_iam_role_policy" "lambda_graph" {
  name   = "lambda_graph"
  role   = "${aws_iam_role.lambda_graph.id}"
  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Effect": "Allow",
        "Resource": "arn:aws:logs:*:*:*"
      }
    ]
  }
  EOF
}
resource "aws_lambda_function" "graph" {
  function_name = "lighthouse_graph"
  s3_bucket     = "${aws_s3_bucket.lighthouse_metrics.id}"
  s3_key        = "${aws_s3_bucket_object.lambda_graph.key}"
  role          = "${aws_iam_role.lambda_graph.arn}"
  handler       = "index.handler"
  runtime       = "nodejs8.10"
  memory_size   = 128

  environment {
    variables = {
      ENTRIES_TABLE_NAME = "${aws_dynamodb_table.lighthouse_metrics_entries.id}"
      JOBS_TABLE_NAME    = "${aws_dynamodb_table.lighthouse_metrics_jobs.id}"
      RUNS_TABLE_NAME    = "${aws_dynamodb_table.lighthouse_metrics_runs.id}"
      REGION             = "${local.aws_region}"
      BUCKET             = "${aws_s3_bucket.lighthouse_metrics.id}"
    }
  }
}

resource "aws_iam_role" "lambda_init" {
  name               = "lambda_init"
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

resource "aws_iam_role_policy" "lambda_init" {
  name   = "lambad_init"
  role   = "${aws_iam_role.lambda_init.id}"

  policy = <<EOF
  {
    "Verson": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "dynamodb:PutItem"
        ],
        "Effect": "Allow",
        "Resource": "${aws_dynamodb_table.lighthouse_metrics_jobs.arn}"
      },
      {
        "Action": [
          "SNS:Publish"
        ],
        "Effect": "Allow",
        "Resource": "${aws_sns_topic.pages_to_test.arn}"
      },
      {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*",
        "Effect": "Allow"
      }
    ]
  }
  EOF
}

resource "aws_lambda_function" "init" {
  function_name = "lighthouse_init"
  s3_bucket     = "${aws_s3_bucket.lighthouse_metrics.id}"
  s3_key        = "${aws_s3_bucket_object.lambda_init.key}"
  role          = "${aws_iam_role.lambda_init.arn}"
  handler       = "index.handler"
  runtime       = "nodejs8.10"
  memory_size   = 2048
  timeout       = 30

  environment {
    variables = {
      REGION          = "${local.aws_region}"
      JOBS_TABLE_NAME = "${aws_dynamodb_table.lighthouse_metrics_jobs.id}"
      SNS_TOPIC_ARN   = "${aws_sns_topic.pages_to_test.arn}"
    }
  }
}

resource "aws_iam_role" "lambda_worker" {
  name               = "lambda_worker"
  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statemest": [
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
resource "aws_iam_role_policy" "lambda_worker" {
  name   = "lambda_worker"
  role   = "${aws_iam_role.lambda_worker.id}"

  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "SNS:Subscribe",
          "SNS:Publish"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_sns_topic.pages_to_test.arn}",
          "${aws_sns_topic.pages_to_test_dlq.arn}"
        ]
      },
      {
        "Action": [
          "dynamodb:UpdateItem",
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_dynamodb_table.lighthouse_metrics_jobs.arn}",
          "${aws_dynamodb_table.lighthouse_metrics_runs.arn}"
        ]
      },
      {
        "Action": [
          "s3:Get*",
          "s3:List*",
          "s3:Put*"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_s3_bucket.lighthouse_metrics.arn}",
          "${aws_s3_bucket.lighthouse_metrics.arn}/*"
        ]
      },
      {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource": "arn:aws:logs:*:*:*",
        "Effect": "Allow"
      }
    ]
  }
  EOF
}

resource "aws_lambda_function" "worker" {
  function_name                  = "lighthouse_worker"
  s3_bucket                      = "${aws_s3_bucket.lighthouse_metrics.id}"
  s3_key                         = "${aws_s3_bucket_object.lambda_worker.key}"
  role                           = "${aws_iam_role.lambda_worker.arn}"
  handler                        = "index.handler"
  runtime                        = "nodejs8.10"
  memory_size                    = "${local.lambda_worker_memory}"
  timeout                        = "${local.lamda_worker_timeout}"
  reserved_concurrent_executions = "3"

  dead_letter_config {
    target_arn = "${aws_sns_topic.pages_to_test_dlq.arn}"
  }

  environment {
    variables = {
      REGION          = "${local.aws_region}"
      JOBS_TABLE_NAME = "${aws_dynamodb_table.lighthouse_metrics_jobs.id}"
      RUNS_TABLE_NAME = "${aws_dynamodb_table.lighthouse_metrics_runs.id}"
      BUCKET          = "${aws_s3_bucket.lighthouse_metrics.id}"
      DLQ_ARN         = "${aws_sns_topic.pages_to_test_dlq.arn}"
    }
  }
}

resource "aws_s3_bucket_object" "lambda_init" {
  bucket = "${aws_s3_bucket.lightouse_metrics.id}"
  key    = "lambdas/v${local.app_version}/init.zip"
  source = "${data.archive_file.lambda_init.output_path}"
  etag   = "${filemd5("lambdas/dist/init.zip")}"
}

resource "aws_s3_bucket_object" "lambda_worker" {
  bucket = "${aws_s3_bucket.lighthouse_metrics.id}"
  key    = "lambdas/v${local.app_version}/worker.zip"
  source = "${data.archive_file.lambda_worker.output_path}"
  etag   = "${filemd5("lambdas/dist/worker.zip")}"
}
resource "aws_s3_bucket_object" "lambda_post_processor" {
  bucket = "${aws_s3_bucket.lighthouse_metrics.id}"
  key    = "lambdas/v${local.app_version}/post-processor.zip"
  source = "${data.archive_file.lambda_post_processor.output_path}"
  etag   = "${filemd5("lambdas/dist/post-processor.zip")}"
}
resource "aws_s3_bucket_object" "lambda_graph" {
  bucket = "${aws_s3_bucket.lighthouse_metrics.id}"
  key    = "lambads/v${local.app_version}/graph.zip"
  source = "${data.archive_file.lambda_graph.output_path}"
  etag   = "${filemd5("lambdas/dist/graph.zip")}"
}

resource "aws_sns_topic_subscription" "pages_to_test" {
  topic_arn = "${aws_sns_topic.pages_to_test.arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.worker.arn}"
}

resource "aws_sns_topic_subscription" "pages_to_test_dlq" {
  topic_arn = "${aws_sns_topic.pages_to_test_dlq.arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.worker.arn}"
}

resource "aws_lambda_permission" "pages_to_test" {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.worker.function_name}"
  principal     = "sns.amasonaws.com"
  source_arn    = "${aws_sns_topic.pages_to_test.arn}"
}

resource "aws_lambda_permission" "pages_to_test_dlq" {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.worker.function_name}"
  principal     = "sns.amazonaws.com"
  source_arn    = "${aws_sns_topic.pages_to_test_dlq.arn}"
}

resource "aws_iam_role" "lambda_post_processor" {
  name               = "lambda_post_processor"
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

resource "aws_iam_role_policy" "lambda_post_processor" {
  name   = "lambda_post_processor"
  role   = "${aws_iam_role.lambda_post_processor.id}"
  policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecordes",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ],
        "Effect": "Allow",
        "Resource": "${aws_dynamodb_table.lighthouse_metrics_jobs.stream_arn}"
      },
      {
        "Action": [
          "dynamodb:UpdateItem"
        ],
        "Effect": "Allow",
        "Resource": "${aws_dynamodb_table.lighthouse_metrics_jobs.arn}"
      },
      {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Effect": "Allow",
        "Resource": "arn:aws:logs:*:*:*"
      },
      {
        "Action": [
          "s3:Get*",
          "s3:List*",
          "s3:Put*"
        ],
        "Effect": "Allow",
        "Resource": [
          "${aws_s3_bucket.lighthouse_metrics.arn}",
          "${aws_s3_bucket.lighthouse_metrics.arn}/*"
        ]
      }
    ]
  }
  EOF
}

resource "aws_lambda_function" "post_processor" {
  function_name = "lighthouse_post_processor"
  s3_bucket     = "${aws_s3_bucket.lighthouse_metrics.id}"
  s3_key        = "${aws_s3_bucket_object.lambda_post_processor.key}"
  role          = "${aws_iam_role.lambda_post_processor.arn}"
  handler       = "index.handler"
  runtime       = "nodejs8.10"
  memory_size   = 128

  environment {
    variables = {
      JOBS_TABLE_NAME = "${aws_dynamodb_table.lighthouse_metrics_jobs.id}"
      REGION          = "${local.aws_region}"
      BUCKET          = "${aws_s3_bucket.lighthouse_metrics.id}"
    }
  }
}

resource "aws_lambda_event_source_mapping" "post_processor" {
  event_source_arn  = "${aws_dynamodb_table.lighthouse_metrics_jobs.stream_arn}"
  function_name     = "${aws_lambda_function.post_processor.arn}"
  starting_position = "LATEST"
  batch_size        = 1
}

resource "template_file" "invoke_lambda_function" {
  template = "${file("lighthouse-parallel.tpl")}"

  vars = {
    lambda_init_arn    = "${aws_lambda_function.init.arn}"
    lambda_init_region = "${local.aws_region}"
    jobs_table_name    = "${aws_dynamodb_table.lighthouse_metrics_jobs.id}"
  }
}

# Archive file
resource "archive_file" "lambda_init" {
  type        = "zip"
  source_dir  = "lambdas/src/worker"
  output_path = "lambdas/dist/worker.zip"
}

resource "archive_file" "lambda_worker" {
  type        = "zip"
  source_dir  = "lambdas/src/worker"
  output_path = "lambdas/dist/worker.zip"
}

resource "archive_file" "lambda_post_processor" {
  type        = "zip"
  source_dir  = "lambdas/src/post-processor"
  output_path = "lambdas/dist/post-processor.zip"
}

resource "archive_file" "lambda_graph" {
  type        = "zip"
  source_dir  = "lambdas/src/graph"
  output_path = "lambdas/dist/graph.zip"
}

resource "local_file" "invoke_lambda_function" {
  content  = "${data.template_file.invoke_lambda_function.rendered}"
  filename = "lighthouse-parallel"
}
