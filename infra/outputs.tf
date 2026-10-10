output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "github_pipeline_role_arn" {
  description = "Set as the AWS_ROLE_ARN repo variable in GitHub"
  value       = aws_iam_role.github_pipeline.arn
}

output "mongo_public_ip" {
  description = "SSH target for the demo (intentionally exposed)"
  value       = aws_instance.mongo.public_ip
}

output "mongo_admin_password" {
  description = "For the demo: terraform output -raw mongo_admin_password"
  value       = random_password.mongo_admin.result
  sensitive   = true
}

output "mongo_private_ip" {
  value = aws_instance.mongo.private_ip
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
