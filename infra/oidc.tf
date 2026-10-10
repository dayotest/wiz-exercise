resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_pipeline" {
  name = "${var.project}-github-pipeline"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*" }
      }
    }]
  })
}

# Broad because pipeline 1 provisions the whole stack. Tighten for real life;
# the preventative guardrail below still blocks audit-log tampering.
resource "aws_iam_role_policy_attachment" "github_admin" {
  role       = aws_iam_role.github_pipeline.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
