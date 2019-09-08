variable "aws_region" {
  description = "aws region to deploy"
  type        = string
}

variable "function_timeout" {
  description = "The amount of time your Lambda Functions has to run in seconds Default 90s"
  default     = 90
  type        = number
}

variable "certbot_server" {
  description = "The URL of let's Encrypt cerbot server"
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  type        = string
}

variable "cloudwatch_log_retention" {
  description = "The cloudwatch log retention ( default 7 days )."
  default     = 7
  type        = number
}

variable "bucket_name" {
  description = "S3 bucket to receive certificates"
  type        = string
}

variable "scan_alarm_clock" {
  description = "time between two scan to search for expired certificates ( in minutes default 1440 = 1 days)"
  type        = number
  default     = 1440
}
