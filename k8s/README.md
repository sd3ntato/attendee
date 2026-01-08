# Kubernetes Manifests for Attendee Service

This directory contains Kubernetes manifests for deploying the attendee bot service to AWS EKS.

## Architecture

The attendee service runs bot pods dynamically in Kubernetes when meetings are scheduled. Bot pods are created on-demand by the attendee API and terminated when the meeting ends.

**Key Components:**
- **Namespace**: `attendee` - Isolated namespace for all attendee resources
- **ServiceAccount**: `attendee-sa` - Uses IRSA (IAM Roles for Service Accounts) for S3 access without hardcoded credentials
- **ConfigMap**: `attendee-config` - Configuration including `LAUNCH_BOT_METHOD=kubernetes` to enable K8s bot creation
- **Secrets**: `attendee-secrets` - Sensitive configuration (DB credentials, Django secrets, etc.)
- **Bot Pods**: Created dynamically by the `BotPodCreator` class when a meeting starts

## Directory Structure

```
k8s/
├── namespaces/
│   └── attendee-namespace.yaml         # Namespace definition
├── base/
│   ├── serviceaccount.yaml             # ServiceAccount with IRSA annotation
│   ├── configmap.yaml                  # Application configuration
│   └── secrets.yaml.template           # Secrets template (DO NOT commit actual secrets)
└── README.md                            # This file
```

## Prerequisites

1. **EKS Cluster**: The `meeting-assistant-eks` cluster must be created and accessible via kubectl
2. **IRSA Role**: The IAM role `meeting-assistant-eks-attendee-attendee-sa-role` must exist with S3 permissions
3. **ECR Image**: The attendee image must be pushed to ECR: `248127682412.dkr.ecr.eu-north-1.amazonaws.com/attendee:v1.0.0`
4. **kubectl context**: Your kubectl must be configured to access the EKS cluster

## Deployment Instructions

### Step 1: Verify EKS Access

```bash
# Configure kubectl
aws eks update-kubeconfig --region eu-north-1 --name meeting-assistant-eks --profile reply

# Verify access
kubectl get nodes
```

### Step 2: Create Namespace

```bash
kubectl apply -f namespaces/attendee-namespace.yaml
```

### Step 3: Create Secrets

**IMPORTANT**: Never commit actual secrets to git. Use the template to create a real secrets file:

```bash
# Copy the template
cp base/secrets.yaml.template base/secrets.yaml

# Edit base/secrets.yaml and replace placeholders:
# - <REPLACE_WITH_DJANGO_SECRET_KEY>
# - <REPLACE_WITH_CREDENTIALS_ENCRYPTION_KEY>
# - <DB_USER> and <DB_PASSWORD>
# - <REPLACE_WITH_GMAIL_PASSWORD>

# Apply secrets
kubectl apply -f base/secrets.yaml

# Delete the local file (don't commit it!)
rm base/secrets.yaml
```

Or create secrets via command line (recommended):

```bash
kubectl create secret generic attendee-secrets \
  --namespace=attendee \
  --from-literal=DJANGO_SECRET_KEY="<value>" \
  --from-literal=CREDENTIALS_ENCRYPTION_KEY="<value>" \
  --from-literal=DATABASE_URL="postgresql://<user>:<password>@meeting-assistant-db-north.caiw1y6ucdp6.eu-north-1.rds.amazonaws.com:5432/meeting-assistant-db-north" \
  --from-literal=GMAIL_ADDRESS="connect.meeting.assistant@gmail.com" \
  --from-literal=GMAIL_PASSWORD="<value>"
```

### Step 4: Apply ConfigMap and ServiceAccount

```bash
kubectl apply -f base/serviceaccount.yaml
kubectl apply -f base/configmap.yaml
```

### Step 5: Verify Deployment

```bash
# Check namespace
kubectl get ns attendee

# Check resources
kubectl get serviceaccount -n attendee
kubectl get configmap -n attendee
kubectl get secrets -n attendee

# Verify IRSA annotation on ServiceAccount
kubectl describe serviceaccount attendee-sa -n attendee | grep eks.amazonaws.com/role-arn
```

## How Bot Pods Are Created

Bot pods are created automatically by the attendee service when a meeting is scheduled. The `BotPodCreator` class in the attendee codebase:

1. Reads configuration from the `attendee-config` ConfigMap
2. Uses the `attendee-sa` ServiceAccount (with IRSA for S3 access)
3. Pulls secrets from `attendee-secrets`
4. Creates a pod with:
   - Image: `248127682412.dkr.ecr.eu-north-1.amazonaws.com/attendee:v1.0.0`
   - Resources: 4 CPU, 4Gi RAM, 10Gi ephemeral storage
   - Command: `python manage.py run_bot --botid <bot_id>`
   - Labels: `app=bot-proc`, `app.kubernetes.io/name=attendee`
   - Namespace: `attendee`

## Testing Bot Pod Creation

To test if bot pod creation works without scheduling a real meeting:

```bash
# SSH to an existing EC2 instance with kubectl access, or use Cloud Shell
# Make sure kubectl is configured

# Manually create a test bot pod (from Python shell)
python manage.py shell

# In Python shell:
from bots.bot_pod_creator import BotPodCreator
creator = BotPodCreator()
result = creator.create_bot_pod(bot_id=999, bot_name="test-bot-999")
print(result)

# Check pod status
kubectl get pods -n attendee -l app=bot-proc
kubectl describe pod test-bot-999 -n attendee
kubectl logs test-bot-999 -n attendee
```

## Configuration Details

### Key Environment Variables (in ConfigMap)

| Variable | Value | Description |
|----------|-------|-------------|
| `LAUNCH_BOT_METHOD` | `kubernetes` | Enables Kubernetes bot creation mode |
| `BOT_POD_NAMESPACE` | `attendee` | Namespace where bot pods are created |
| `BOT_POD_IMAGE` | `248127682412.dkr.ecr.eu-north-1.amazonaws.com/attendee` | ECR image for bot pods |
| `BOT_POD_SERVICE_ACCOUNT_NAME` | `attendee-sa` | ServiceAccount with IRSA for S3 |
| `USE_IRSA_FOR_S3_STORAGE` | `true` | Use IRSA instead of hardcoded AWS credentials |
| `REDIS_URL` | `redis://172.31.16.245:6379` | EC2 Redis instance (stays on EC2) |

### IRSA (IAM Roles for Service Accounts)

The `attendee-sa` ServiceAccount has an annotation linking it to an IAM role:

```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::248127682412:role/meeting-assistant-eks-attendee-attendee-sa-role
```

This allows bot pods to access S3 without hardcoded AWS credentials. The IAM role has permissions to:
- Read/write/list objects in `meeting-assistant-projects` bucket
- No other AWS permissions (principle of least privilege)

### Security Context

Bot pods run with security hardening:
- Non-root user (UID 1000)
- Dropped all capabilities
- No privilege escalation
- Seccomp profile: `Unconfined` (required for Chrome sandboxing)

## Monitoring

```bash
# Watch all pods in attendee namespace
kubectl get pods -n attendee --watch

# Get logs from a bot pod
kubectl logs -f <pod-name> -n attendee

# Describe a bot pod (to see events and status)
kubectl describe pod <pod-name> -n attendee

# Delete a stuck bot pod
kubectl delete pod <pod-name> -n attendee --grace-period=60
```

## Troubleshooting

### Bot pod creation fails with "Forbidden"

Check IRSA role and trust policy:
```bash
kubectl describe serviceaccount attendee-sa -n attendee
aws iam get-role --role-name meeting-assistant-eks-attendee-attendee-sa-role --profile reply
```

### Bot pod stuck in "Pending"

Check node availability and resources:
```bash
kubectl get nodes
kubectl describe pod <pod-name> -n attendee
# Look for "Insufficient cpu" or "Insufficient memory"
```

If bot node group is scaled to 0, it should auto-scale. Check:
```bash
kubectl get nodes -l role=bot
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
```

### Bot pod can't connect to RDS

Check security groups allow EKS nodes to access RDS on port 5432:
```bash
# From a bot pod:
kubectl exec -it <pod-name> -n attendee -- curl -v telnet://meeting-assistant-db-north.caiw1y6ucdp6.eu-north-1.rds.amazonaws.com:5432
```

### Bot pod can't connect to EC2 Redis

Check security groups allow EKS nodes to access EC2 Redis on port 6379:
```bash
# From a bot pod:
kubectl exec -it <pod-name> -n attendee -- curl -v telnet://172.31.16.245:6379
```

## Cleanup

To remove all resources:

```bash
kubectl delete namespace attendee
```

This will delete all pods, services, configmaps, secrets, and serviceaccounts in the namespace.
