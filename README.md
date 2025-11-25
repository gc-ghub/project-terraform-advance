# project-terraform-advance
This repository demonstrates an intermediate-to-advanced Terraform project that provisions an AWS application stack with cross-region S3 replication, server-backed webservers, Lambda-backed APIs (presign & EC2 metadata), DynamoDB processing, and SNS notifications.

**What It Shows**
- **Cross-region S3 replication**: primary S3 bucket in the main region and a replica bucket in a secondary region with a dedicated replication IAM role.
- **EC2 webservers**: an autoscaled-like set of EC2 instances (controlled by `count_of_instances`) across AZs, provisioned with a user-data script serving a small frontend via Nginx.
- **Serverless APIs**: API Gateway + Lambda functions for (a) fetching EC2 metadata and (b) issuing presigned S3 upload URLs.
- **Event-driven processing**: S3 -> Lambda (in replica region) -> DynamoDB + SNS for replication events.
- **Terraform best-practices**: remote state backend (S3), multiple provider aliases (primary & secondary regions), use of `archive` provider to package Lambdas.

**Repository Layout**
- `stark_industries/` — Terraform module and assets
	- `main.tf`, `providers.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `data.tf`, ... : core Terraform resources
	- `s3_bucket.tf` : S3 buckets, versioning, replication, lifecycle and related IAM
	- `lambda_ec2.tf`, `lambda_s3.tf`, `presigner.tf` : Lambda functions and API Gateway configuration
	- `keypair.tf` : generates an RSA keypair and saves the private key locally after `apply`
	- `stark_industries_website.sh.tpl` : EC2 user-data template (Nginx + frontend that calls APIs)
	- `lambda/` : Lambda Python sources — `get_ec2_metadata.py`, `presigner.py`, `process_replica.py`

**Important Files**
- `stark_industries/terraform.tfvars` : example runtime variable values (project name, AMI, instance settings, VPC ID, API stage, alert email)
- `stark_industries/outputs.tf` : exports like bucket names, API invoke URLs, Lambda ARNs, EC2 public IPs, and convenient SSH commands

**Architecture Overview**
- Primary region (provider `aws`):
	- `aws_s3_bucket.main_bucket` — main storage bucket (versioned, SSE enabled)
	- `aws_s3_bucket.logging_bucket` — access logging bucket
	- `aws_s3_bucket_replication_configuration` — replication to the secondary region
	- `aws_lambda_function.presigner` — presigned URL generator (exposed via API Gateway)
	- `aws_lambda_function.get_metadata` — returns EC2 instances metadata (exposed via API Gateway)
	- EC2 webservers with `stark_industries_website.sh.tpl` user-data
- Secondary region (provider `aws.secondary`):
	- `aws_s3_bucket.replica_bucket` — receives replicated objects
	- `aws_lambda_function.process_replica` — triggered by S3 events to write metadata to DynamoDB and publish to SNS

**Prerequisites**
- `terraform` >= 1.13.3 (as pinned in `providers.tf`)
- `aws` CLI configured with credentials that have permissions to create resources across both regions (`ap-south-1` and `ap-southeast-1` as used in `providers.tf`)
- Optional: `python` for local testing of Lambda code, and `curl` for API calls

**Quick Start (example)**
1. Inspect and adjust variables in `stark_industries/terraform.tfvars` (especially `vpc_id`, `alert_email`, and `count_of_instances`).
2. Initialize Terraform and providers from the repo root:

```powershell
cd .\stark_industries
terraform init
```

3. (Optional) Review the plan:

```powershell
terraform plan -out plan.tfplan
```

4. Apply the plan:

```powershell
terraform apply "plan.tfplan"
# or directly
terraform apply -auto-approve
```

Notes:
- Terraform uses an S3 backend `tf-remote-backend-stark-industries` defined in `providers.tf`. Ensure your AWS credentials can access that backend.
- The `keypair.tf` resource writes a PEM file into the module directory named like `` `stark-industries-<workspace>-key.pem` `` — secure this file and set appropriate permissions.

**Useful Outputs**
- To view all outputs after apply:

```powershell
terraform output
```

- Important outputs (available in `stark_industries/outputs.tf`):
	- `main_bucket` : name of the main S3 bucket
	- `replica_bucket` : name of the replica bucket
	- `metadata_api_url` : URL for the EC2 metadata API
	- `upload_api_invoke_url` : URL for the presign/upload API
	- `webserver_public_ips` : array of public IPs for webservers
	- `ssh_commands` : suggested SSH commands for accessing webservers (uses the generated PEM)

**Presign API Usage (example)**
1. Request a presigned URL (replace `<PRESIGN_API_URL>` with `upload_api_invoke_url`):

```powershell
# PowerShell (Invoke-RestMethod)
$body = @{ filename = 'myfile.txt'; content_type = 'text/plain' } | ConvertTo-Json
$presign = Invoke-RestMethod -Method Post -Uri '<PRESIGN_API_URL>' -Body $body -ContentType 'application/json'
$presign | ConvertTo-Json -Depth 5

# The response includes `url` (presigned PUT URL) and `key` (S3 object key)
```

2. Upload the file to S3 using the `url` returned:

```powershell
# Use curl (available on recent Windows builds) or Invoke-WebRequest
curl -X PUT -H "Content-Type: text/plain" --upload-file .\myfile.txt "<PRESIGNED_URL_FROM_RESPONSE>"
```

After upload the replication (to the replica bucket) will trigger `process_replica` Lambda in the secondary region which writes to DynamoDB and publishes to SNS.

**EC2 Website & Frontend**
- The EC2 user-data installs Nginx and writes a small UI (`index.html`) which calls the `metadata_api_url` and the presign endpoint for uploads. The template is `stark_industries/stark_industries_website.sh.tpl`.

**Lambda Code Location**
- `stark_industries/lambda/get_ec2_metadata.py` — metadata API implementation
- `stark_industries/lambda/presigner.py` — presign service (generates presigned PUT URLs)
- `stark_industries/lambda/process_replica.py` — processes S3 events from replica bucket and writes to DynamoDB + SNS

**Security & Cost Notes**
- Buckets are created with `force_destroy = true` for convenience in labs — this will remove all objects when destroying the bucket. Remove or change this for production.
- IAM policies included are scoped for the demo, but you should tighten resource ARNs and permissions for production.
- Watch out for costs from EC2, Lambda invocations, API Gateway, DynamoDB, SNS, and S3 requests/storage.

**Troubleshooting**
- If APIs return 403 when invoking Lambda: ensure `aws_lambda_permission` and API Gateway source ARNs are correct and deployment was created.
- If replication does not occur: verify versioning is enabled on both buckets and that the replication role policy allows access to source and destination buckets.
- For API Gateway changes, Terraform performs deployments via `aws_api_gateway_deployment` with triggers — if you update methods/integrations, redeployment should happen automatically but you can force a re-deploy by changing a trigger input.

**Clean Up**
- To remove everything provisioned by Terraform:

```powershell
cd .\stark_industries
terraform destroy -auto-approve
```

- After destroy, remove the generated PEM file(s) in the module folder (e.g. `stark-industries-<workspace>-key.pem`) if present and no longer needed.

**Contributing & Extensions**
- To extend: add more strict IAM policies, move sensitive items to AWS Secrets Manager, add CloudWatch dashboards, or add CI (GitHub Actions) to validate `terraform fmt` / `terraform validate` before merging.

**CI/CD (GitHub Actions)**
- This repository includes GitHub Actions workflows to validate, plan, apply, and destroy Terraform infrastructure.
- Workflows present in `.github/workflows/`:
	- `terraform-pr.yml` — runs on `pull_request` (branches: `dev`, `main`): checks `terraform fmt`, `terraform validate`, selects workspace (`dev` or `prod` depending on base branch), and runs `terraform plan`. It posts the plan as a sticky PR comment and uploads the plan as an artifact.
	- `terraform-apply-dev.yml` — runs on `push` to `dev` and applies the plan to the `dev` workspace automatically.
	- `terraform-apply-prod.yml` — runs on `push` to `main` and applies to the `prod` workspace. This workflow references a GitHub `environment` named `prod` — configure it in repository settings and require reviewers/approvals if desired.
	- `terraform-destroy.yml` — manual `workflow_dispatch` to destroy either `dev` or `prod` workspace.

- Important behavior and notes:
	- Terraform version used in workflows is pinned to `1.13.3` (match this locally if you run Terraform from CLI).
	- Workspaces: the workflows select or create workspaces named `dev` and `prod`. PR checks choose workspace by the PR base branch (`main` => `prod`, otherwise `dev`).
	- Plan visibility: `terraform-pr.yml` posts plan output to the PR using `marocchino/sticky-pull-request-comment` (plan is also uploaded as an artifact). Very large plans may be truncated in comments — check the uploaded `plan.txt` artifact if needed.
	- Secrets required (set these in repository Secrets):
		- `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` — credentials used by Actions to perform Terraform operations.
		- `AWS_REGION` — used by some workflows (`ap-south-1` is used in examples; change as needed).
		- `VPC_ID` — used by workflows to set `TF_VAR_vpc_id` when running (the workflows inject some `TF_VAR_` environment variables).
		- `GITHUB_TOKEN` is provided automatically to workflows for commenting; no manual config required.
	- Environment protection: configure the `prod` GitHub Environment to require manual approvals or reviewers before the `terraform-apply-prod.yml` job runs.

- How to run / trigger:
	- Open a PR against `dev` or `main` — `terraform-pr.yml` will run automatically and post a plan comment.
	- Push to `dev` to automatically apply to the `dev` workspace.
	- Push to `main` to automatically apply to `prod` (recommended to protect the `prod` environment with reviewers).
	- To destroy a workspace use the `Terraform Destroy` workflow from the Actions tab (select `dev` or `prod`).

- Recommended repository setup steps:
	1. Add required secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `VPC_ID`, and optionally `AWS_REGION`.
	2. Configure a `prod` GitHub Environment (Settings → Environments) and require reviewers/approvals for added safety.
	3. Optionally add an IAM user/role for CI with least privilege for the Terraform resources and store its keys in repository Secrets.



