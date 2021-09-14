terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
  region = var.aws_region
}

/**
Create a document cluster instance
*/
resource "aws_docdb_cluster_instance" "cluster_instances" {
  count              = 1
  identifier         = "docdb-${count.index}"
  cluster_identifier = aws_docdb_cluster.default.id
  instance_class     = "db.t3.medium"
}

/**
Create a document cluster
*/
resource "aws_docdb_cluster" "default" {
  cluster_identifier = "docdb-cluster-demo"
  availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
  master_username    = "foo"
  master_password    = "barbut8chars"
  backup_retention_period = 5
  deletion_protection = true
  skip_final_snapshot     = true
}

/**
Create a renadom animal name for the buckets
*/
resource "random_pet" "lambda_bucket_name" {
  prefix = "example-terraform-functions"
  length = 4
}

/**
Create S3 bucket.
*/
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = random_pet.lambda_bucket_name.id

  acl           = "private"
  force_destroy = true
}

/**
Zip lambda function and modules.
*/
data "archive_file" "terraforma_lambda_example" {
  type = "zip"

  source_dir  = "${path.module}/terraforma_lambda_example"
  output_path = "${path.module}/terraforma_lambda_example.zip"
}

/**
Add ziped lambda function to S3.
*/
resource "aws_s3_bucket_object" "terraforma_lambda_example" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "terraforma_lambda_example.zip"
  source = data.archive_file.terraforma_lambda_example.output_path

  etag = filemd5(data.archive_file.terraforma_lambda_example.output_path)
}

/** 
Create the lambda function.
**/
resource "aws_lambda_function" "terraforma_lambda_example" {
  function_name = "terraforma-lambda-example"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_bucket_object.terraforma_lambda_example.key

  runtime = "nodejs12.x"
  handler = "main.handler"

  source_code_hash = data.archive_file.terraforma_lambda_example.output_base64sha256

  role = aws_iam_role.lambda_exec.arn
}

/** 
Create cloudwatch for the lambda function.
**/
resource "aws_cloudwatch_log_group" "terraforma_lambda_example" {
  name = "/aws/lambda/${aws_lambda_function.terraforma_lambda_example.function_name}"

  retention_in_days = 30
}

/** 
Create iam role for the lambda function.
**/
resource "aws_iam_role" "lambda_exec" {
  name = "serverless_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}

/**
Attache AWSLambdaBasicExecutionRole policy to the IAM role.
This policy allows lambda function to write to CloudWatch logs.
*/
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

/**
API Gateway name and protocol
*/
resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

/**
Stage for the API Gateway with access logging enabled
*/
resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id
  
  name        = "serverless_lambda_stage"
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

/**
Configures API Gateway to use your Lambda function
*/
resource "aws_apigatewayv2_integration" "terraforma_lambda_example" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.terraforma_lambda_example.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"

  environment {
    variables = aws_docdb_cluster_instance.cluster_instances
  }
  
}

/**
Map HTTP request to a target
*/
resource "aws_apigatewayv2_route" "terraforma_lambda_example" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.terraforma_lambda_example.id}"
}

/**
Define a log group to store access logs for the aws_apigatewayv2_stage.lambda API Gateway stage
*/
resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

/**
Gives API Gateway permission to invoke the Lambda function
*/
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terraforma_lambda_example.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

/**
version = v1.0.0
*/
