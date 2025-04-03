# AWS credentials for CloudWatch data sources
variable "aws_access_key" {
  description = "AWS access key for CloudWatch data sources"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key for CloudWatch data sources"
  type        = string
  default     = ""
  sensitive   = true
} 