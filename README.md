# Learn Terraform - Lambda functions and API Gateway

AWS Lambda functions and API gateway are often used to create serverlesss applications.

Follow along with this [tutorial on HashiCorp
Learn](https://learn.hashicorp.com/tutorials/terraform/lambda-api-gateway?in=terraform/aws).

#Commands :

//List bucket
aws s3 ls $(terraform output -raw lambda_bucket_name)

//Invoke remote lambda
aws lambda invoke --region=us-east-1 --function-name=$(terraform output -raw function_name) response.json

//Invoke remote api endpoint
curl "$(terraform output -raw base_url)/hello"