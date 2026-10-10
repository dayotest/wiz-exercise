variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "wiz-exercise"
}

variable "your_name" {
  description = "Goes into wizexercise.txt (set in the app image build) and resource tags"
  type        = string
}

variable "github_repo" {
  description = "owner/repo that is allowed to assume the pipeline role via OIDC"
  type        = string
}

variable "admin_principal_arns" {
  description = "IAM user/role ARNs (you) that get EKS cluster-admin. The GitHub pipeline role is added automatically."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair, so you can actually SSH into the Mongo VM for the demo"
  type        = string
  default     = ""
}

variable "mongo_instance_type" {
  type    = string
  default = "t3.small"
}

variable "eks_node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "enable_scp" {
  description = "Create an SCP preventative control. Needs AWS Organizations management-account rights; leave false in CloudLabs."
  type        = bool
  default     = false
}

variable "scp_target_id" {
  description = "OU or account ID to attach the SCP to when enable_scp = true"
  type        = string
  default     = ""
}
