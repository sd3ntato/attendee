# Kubernetes Deployment Guide

This guide explains how to deploy Attendee bot pods to Kubernetes (EKS).

## Architecture

```
EKS Cluster
  ↓
Bot Pods (dynamically created via BotPodCreator)
  ├→ PostgreSQL (on EC2 attendee instance)
  ├→ Redis (on EC2 attendee instance)
  └→ S3 (via AWS credentials)
```

Bot pods are created dynamically by the BotPodCreator when a bot is requested via the API. Each bot runs in its own Kubernetes pod.

## Prerequisites

1. **EKS Cluster** - Running Kubernetes 1.34 or later
2. **kubectl** - Configured to access your EKS cluster
3. **ECR Repository** - For storing bot Docker images
4. **EC2 Attendee Instance** - Running PostgreSQL and Redis (or use RDS/ElastiCache)
5. **AWS Credentials** - For S3 access

## Quick Setup

Run the setup script to create all necessary Kubernetes resources:

```bash
./setup-k8s.sh
```

This will create:
- Namespace: `attendee-bots`
- ServiceAccount: `attendee-sa`
- Secret: `attendee-secrets` (AWS credentials)
- ConfigMap: `attendee-config` (environment variables)

## Manual Setup

If you prefer to create resources manually:

### 1. Create Namespace

```bash
kubectl create namespace attendee-bots
```

### 2. Create Service Account

```bash
kubectl create serviceaccount attendee-sa -n attendee-bots
```

### 3. Create Secrets

```bash
kubectl create secret generic attendee-secrets \
  --from-literal=AWS_ACCESS_KEY_ID="<your-key>" \
  --from-literal=AWS_SECRET_ACCESS_KEY="<your-secret>" \
  --from-literal=AWS_REGION="eu-north-1" \
  -n attendee-bots
```

### 4. Create ConfigMap

**CRITICAL:** The ConfigMap must include these specific environment variables:

```bash
kubectl create configmap attendee-config \
  --from-literal=DJANGO_SETTINGS_MODULE="attendee.settings.development" \
  --from-literal=POSTGRES_HOST="172.31.16.245" \
  --from-literal=DATABASE_NAME="attendee_development" \
  --from-literal=DB_HOST="172.31.16.245" \
  --from-literal=DB_PORT="5432" \
  --from-literal=REDIS_URL="redis://172.31.16.245:6379/5" \
  --from-literal=REDIS_HOST="172.31.16.245" \
  --from-literal=REDIS_PORT="6379" \
  --from-literal=AWS_RECORDING_STORAGE_BUCKET_NAME="attendee-recordings" \
  --from-literal=AWS_S3_SIGNATURE_VERSION="s3v4" \
  -n attendee-bots
```

**Why these specific variables?**
- `DJANGO_SETTINGS_MODULE` - Django won't load the `bots` app without this
- `POSTGRES_HOST` - Django's `settings.development.py` specifically reads this variable (not `DB_HOST`)
- `REDIS_URL` - BotController expects the full URL format with database number

## Configuration

### Environment Variables

Update your `dev.docker-compose.yaml` (or production config) with these Kubernetes-specific environment variables:

```yaml
environment:
  - LAUNCH_BOT_METHOD=kubernetes
  - CUBER_APP_NAME=attendee
  - CUBER_RELEASE_VERSION=v1.0.2
  - BOT_POD_IMAGE=<account-id>.dkr.ecr.eu-north-1.amazonaws.com/meeting-assistant/attendee
  - BOT_POD_NAMESPACE=attendee-bots
  - BOT_POD_SERVICE_ACCOUNT_NAME=attendee-sa
  - BOT_POD_CONFIG_MAP_NAME=attendee-config
  - BOT_POD_SECRETS_NAME=attendee-secrets
  - DISABLE_BOT_POD_IMAGE_PULL_SECRET=true
  - BOT_CPU_REQUEST=700m
  - BOT_MEMORY_REQUEST=1500Mi
  - BOT_MEMORY_LIMIT=2Gi
```

### Networking

Bot pods need to connect to:
1. **PostgreSQL** - Ensure EKS node security group allows traffic to EC2 on port 5432
2. **Redis** - Ensure EKS node security group allows traffic to EC2 on port 6379
3. **EKS API** - Ensure EC2 can reach EKS API on port 443 (for BotPodCreator)

## Push Image to ECR

Before bots can run, push the Docker image to ECR:

```bash
# Login to ECR
aws ecr get-login-password --region eu-north-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.eu-north-1.amazonaws.com

# Tag image
docker tag attendee-attendee-app-local:latest \
  <account-id>.dkr.ecr.eu-north-1.amazonaws.com/meeting-assistant/attendee:v1.0.2

# Push image
docker push <account-id>.dkr.ecr.eu-north-1.amazonaws.com/meeting-assistant/attendee:v1.0.2
```

## Testing

Create a test bot to verify everything is working:

```bash
curl -X POST http://<attendee-api>/api/v1/bots \
  -H "Authorization: Token <your-api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "meeting_url": "<teams-or-zoom-url>",
    "bot_name": "Test Bot"
  }'
```

Watch for the pod to be created:

```bash
kubectl get pods -n attendee-bots -w
```

Check pod logs:

```bash
kubectl logs -f <pod-name> -n attendee-bots
```

## Troubleshooting

### Pod fails with "Unknown command: 'run_bot'"

**Cause:** Missing `DJANGO_SETTINGS_MODULE` in ConfigMap

**Fix:** Update ConfigMap to include `DJANGO_SETTINGS_MODULE=attendee.settings.development`

### Pod fails with database connection error

**Cause:** Missing `POSTGRES_HOST` or wrong database hostname

**Fix:** Ensure ConfigMap has `POSTGRES_HOST` (not just `DB_HOST`) pointing to your PostgreSQL server

### Pod fails with Redis connection error

**Cause:** Missing `REDIS_URL` or wrong Redis URL format

**Fix:** Ensure ConfigMap has `REDIS_URL=redis://<host>:<port>/<db-number>`

### Pods stuck in Pending with "Insufficient cpu"

**Cause:** Requesting more CPU than available on nodes

**Fix:** Reduce `BOT_CPU_REQUEST` in your configuration (t3.large has ~1.9 CPU allocatable)

## Production Considerations

For production deployments:

1. **Use managed services:**
   - RDS for PostgreSQL
   - ElastiCache for Redis
   - Update `POSTGRES_HOST` and `REDIS_URL` accordingly

2. **Create production settings:**
   - Create `attendee/settings/kubernetes.py` or `attendee/settings/production.py`
   - Update ConfigMap: `DJANGO_SETTINGS_MODULE=attendee.settings.production`

3. **Security:**
   - Use IRSA (IAM Roles for Service Accounts) instead of hardcoded AWS credentials
   - Enable pod security policies
   - Use network policies to restrict traffic

4. **Scaling:**
   - Use Karpenter or Cluster Autoscaler for node scaling
   - Configure HPA (Horizontal Pod Autoscaler) if needed
   - Monitor costs with node right-sizing

## Resources

- Infrastructure code: `meeting-assistant-infrastructure/`
- Bot pod creator: `attendee/bots/bot_pod_creator/`
- Deployment plan: `.claude/plans/concurrent-chasing-sky.md`
