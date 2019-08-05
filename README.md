# aws-lambda-lighthouse

## Requirements

- AWS Account
- AWS access credentials
- nodejs 8.10
- terraform v0.12.3
- yarn

## Deploy

- `touch lambdas/dist/init.zip lambdas/dist/post-processor.zip lambdas/dist/worker.zip lambdas/dist/graph.zip`.
- `yarn` to install dependencies inside each of the `lambdas/src` directiories.
- Change the `locals` block in `infra.tf` as needed for your org name, region, creds file path, etc.
- `terraform init`
- `terraform plan`
- `terraform apply`
