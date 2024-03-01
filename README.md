# amazon-eks-chaos

# Requirements
* docker-compose
* docker
* kubectl
* eksctl
* git-remote-codecommit
* terraform
* aws-cli
* jq

# Setup

## Clone your repo

## Local (Just for testing)

### Deploy

```bash
docker-compose -f deploy/docker/docker-compose.yaml up -d --build
```

### Test

```bash
curl localhost:5000/healthz
```

### Clean up

```bash
docker-compose -f deploy/docker/docker-compose.yaml down --remove-orphans
```

## Setup env vars

Export these env vars locally:

```bash
AWS_ACCOUNT_ID=<Replace with your AWS account id>
```

## AWS

### Deploy Terraform resources

```bash
cd deploy/terraform
terraform init
terraform plan
terraform apply --auto-approve
```

This will take 20-30 minutes. It deploys VPC, and the observability resources and codecommit for ArgoCD to watch and EKS resources including networking components, and RDS and AWS Secrets Manager.

**Note** 

if you run into the following errors, please just rerun `terraform apply --auto-approve`. As it is awaiting for the `cert-manager` to be installed first before the `ADOT` managed addon can be applied.

```bash
│ Error: waiting for EKS Add-On (chaos-cluster:adot) create: unexpected state 'CREATE_FAILED', wanted target 'ACTIVE'. last error: : K8sResourceNotFound: cert-manager is not installed on this cluster. During preview, you are required to have previously installed cert-manager.
│ 
│   with module.cluster.module.eks.aws_eks_addon.this["adot"],
│   on .terraform/modules/cluster.eks/main.tf line 492, in resource "aws_eks_addon" "this":
│  492: resource "aws_eks_addon" "this" {
```

### Set up the CodeCommit Repository

(1) Create a new folder outside of your existing repo.

(2) Go to the AWS Console -> Codecommit to find your CodeCommit Repo. And follow the guideline (i.e. HTTPS(GRC) or HTTPS) to set it up. Below example is following the sample from `HTTP(GRC)`

```bash
pip install git-remote-codecommit
git clone codecommit::<region-name>://chaos_gitops_repository

```

(3) Copy the `ecommerce-app` folder into the repo folder.

(4) perform an initial commit


Replace required values in `values.yaml`:

1. Replace `db_uri` in `deploy/k8s/helm/ecommerce-app/values.yaml` with your RDS endpoint created via the Terraform. Can retrieve it via the AWS Console or via the below command:

```bash
aws rds describe-db-instances --db-instance-identifier chaos-cluster-rds --query 'DBInstances[*].Endpoint.Address' --output text
```

2. Replace `POSTGRES_PASSWORD` in `deploy/k8s/helm/ecommerce-app/templates/database.yaml` with the secrets manager. Follow the below steps. Alternatively retrieve it via AWS Secrets Manger Console

```bash
# Retrieve the ARN of the Database AWS Secrets Manager
terraform output rds_password_secrets_manager_arn

# Replace <your-secret-id-or-name> with the ARN above (removing the "", do remember to keep the ''
aws secretsmanager get-secret-value --secret-id '<your-secret-id-or-name>' --query SecretString | jq -r "." | jq -r ".password"
```

3. Replace `repoURL` in `deploy/k8s/helm/argocd/values.yaml` with codecommit_full_endpoint

```bash
terraform output codecommit_full_endpoint 
```

Before this step, ensure you have `git-remote-codecommit` installed locally. Refer to [AWS Official Document](https://docs.aws.amazon.com/codecommit/latest/userguide/setting-up-git-remote-codecommit.html)

```bash
git add .
git commit -m "files for argocd"
git push -u codecommit main
```

Assign Grafana user access (ensure you have AWS SSO user created beforehand):
1. Navigate to AWS Console
2. Navigate to Amazon Grafana
3. Under Authentication, assign your user Admin access

### Create other resources

Create the IAM resources required for AWS FIS:

```bash
cd deploy/iam

aws iam create-role --role-name fis-eks-experiment \
  --assume-role-policy-document file://fis_trust.json

aws iam put-role-policy --role-name fis-eks-experiment \
  --policy-name fis-eks-policy \
  --policy-document file://fis_policy.json

eksctl create iamidentitymapping \
  --cluster chaos-cluster \
  --arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/fis-eks-experiment \
  --username chaos-experiment
```

### Access ArgoCD

Get ArgoCD login url:

```bash
export ARGOCD_SERVER=`kubectl get svc argo-cd-argocd-server -n argocd -o json | jq --raw-output '.status.loadBalancer.ingress[0].hostname'`
echo "https://$ARGOCD_SERVER"
```

Get ArgoCD password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Login to ArgoCD with username admin and password as retrieved from step above.

## Clean experiments

```bash
kubectl delete chaosengine,chaosexperiments,chaosresults --all -n ecommerce-app
```


## Clean Up

```bash
terraform apply --destroy --auto-approve
```

Delete the AWS Cloudwatch Log Group `/aws/eks/chaos-cluster/cluster`. 