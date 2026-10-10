# Wiz Technical Exercise: AWS build

Terraform + GitHub Actions for the two-tier app. Weaknesses are intentional and tagged `INTENTIONAL WEAKNESS` in the code.

## One-time setup
1. Create an S3 bucket for Terraform state (CloudLabs account, us-east-1).
2. Push this repo to GitHub. Copy the sample todo app (https://github.com/jeffthorne/tasky) into `app/` next to the Dockerfile and check the Dockerfile paths against it.
3. First apply from your laptop (the pipeline role does not exist yet):
   ```
   cd infra
   terraform init -backend-config="bucket=<state-bucket>" -backend-config="key=wiz-exercise/terraform.tfstate" -backend-config="region=us-east-1" -backend-config="use_lockfile=true"
   terraform apply -var="your_name=<Your Name>" -var="github_repo=<owner>/<repo>" \
     -var='admin_principal_arns=["<your IAM user or role ARN>"]' -var="ssh_key_name=<your EC2 key pair>"
   ```
   (`aws sts get-caller-identity` shows your ARN. For an assumed role, use the role ARN, not the session ARN.)
4. Set GitHub repo **variables**: `AWS_ROLE_ARN` (output), `AWS_REGION`, `TF_STATE_BUCKET`, `ECR_REPO` (`wiz-exercise-todo`), `CLUSTER_NAME` (`wiz-exercise-eks`), `YOUR_NAME`, `SSH_KEY_NAME`, and `ADMIN_PRINCIPAL_ARNS` (same list as above as JSON, e.g. `["arn:aws:iam::123:user/me"]`, otherwise pipeline 1 removes your cluster access).
5. Push to `main`: pipeline 1 re-plans the infra, pipeline 2 builds, scans, pushes and deploys.

## Repo protections (do in GitHub settings, not code)
Branch protection on `main`, secret scanning + push protection, Dependabot alerts, code scanning.

## Demo commands
```
kubectl get pods,svc,ingress -n todo
kubectl -n todo exec deploy/todo -- cat /app/wizexercise.txt
kubectl auth can-i '*' '*' --as=system:serviceaccount:todo:todo-app
ssh ubuntu@<mongo_public_ip>
curl https://<backup_bucket>.s3.amazonaws.com/        # public listing
```

## Teardown
Run `terraform destroy` from your own admin identity, not the pipeline. The guardrail deny on the pipeline role blocks deleting CloudTrail, Config and GuardDuty, on purpose.

## Likely collisions in a shared or pre-used account
- Existing GitHub OIDC provider, GuardDuty detector, Config recorder, or Security Hub: `terraform import` them or drop that resource.
- Account-level S3 Block Public Access ON: the public backup bucket will be refused until it is turned off.
- The app user has readWrite on both `todos` and `go-mongodb`; confirm which database name the sample app uses.

## Known caveats
- Not applied against a real account yet; run `terraform validate` and expect a round or two of fixes.
- CloudLabs may block Organizations (SCP), GuardDuty features, or Security Hub. The IAM deny guardrail works regardless.
- Ubuntu 20.04 and Mongo 4.4 packages must still be reachable from the Canonical and MongoDB repos; test the VM first.
- Destroy order: empty the ECR repo and delete the ALB ingress before `terraform destroy`.
