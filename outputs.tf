output "bucket_arn" {
  description = "The ARN of certificates repository"
  value       = aws_s3_bucket.this.arn
}

output "sqs_request_arn" {
  description = "The SQS ARN of queue for request of renew cerificates"
  value       = aws_sqs_queue.this.arn
}

output "find_expired_certificates_lambda_arn" {
  description = "The Lambda ARN of Find certificates to refresh by Let's Encrypt"
  value       = aws_lambda_function.find_expired_certificates.arn
}

output "invoke_cerbot_lambda_arn" {
  description = "The Lambda ARN of Invoke Let's Encrypt to refresh certificate"
  value       = aws_lambda_function.invoke_cerbot.arn
}

output "sns_result_arn" {
  description = "The SNS result ARN of topic for result of renew cerificates"
  value       = aws_sns_topic.this.arn
}
