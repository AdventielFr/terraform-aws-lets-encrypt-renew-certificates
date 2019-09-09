
provider "aws" {
  region = "eu-west-3"
}

module "lets_and_script_renew_certificates" {
  source      = "../"
  aws_region  = "eu-west-3"
}

output "bucket_arn" {
  description = "The ARN of certificates repository"
  value       = module.lets_and_script_renew_certificates.bucket_arn
}

output "sqs_request_arn" {
  description = "The SQS ARN of queue for request of renew cerificates"
  value       = module.lets_and_script_renew_certificates.sqs_request_arn
}

output "invoke_cerbot_lambda_arn" {
  description = "The Lambda ARN of Invoke let's and script to refresh certificate"
  value       = module.lets_and_script_renew_certificates.invoke_cerbot_lambda_arn
}

output "find_expired_certificates_lambda_arn" {
  description = "The Lambda ARN of Find certificates to refresh by let's and script"
  value       = module.lets_and_script_renew_certificates.find_expired_certificates_lambda_arn
}

output "sns_result_arn" {
  description = "The SNS result ARN of topic for result of renew cerificates"
  value       = module.lets_and_script_renew_certificates.sns_result_arn
}

