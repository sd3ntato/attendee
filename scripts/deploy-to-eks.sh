#!/bin/bash
set -euo pipefail

# Usage: ./deploy-to-eks.sh <aws-profile>
# Example: ./deploy-to-eks.sh reply

if [ $# -lt 1 ]; then
    echo "Error: AWS profile is required"
    echo "Usage: $0 <aws-profile>"
    echo "Example: $0 reply"
    exit 1
fi

AWS_PROFILE="$1"
NAMESPACE="attendee"
AWS_REGION="eu-north-1"
CLUSTER_NAME="meeting-assistant-eks"

echo "============================================"
echo "Deploying Attendee to EKS"
echo "AWS Profile: ${AWS_PROFILE}"
echo "Cluster: ${CLUSTER_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "============================================"

# Verify required env vars for secrets
: "${DB_USER?Error: DB_USER environment variable is required}"
: "${DB_PASSWORD?Error: DB_PASSWORD environment variable is required}"
: "${DJANGO_SECRET_KEY?Error: DJANGO_SECRET_KEY environment variable is required}"
: "${CREDENTIALS_ENCRYPTION_KEY?Error: CREDENTIALS_ENCRYPTION_KEY environment variable is required}"

echo ""
echo "1. Configuring kubectl..."
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME} --profile ${AWS_PROFILE}

echo ""
echo "2. Creating namespace..."
kubectl apply -f k8s/namespaces/attendee-namespace.yaml

echo ""
echo "3. Creating ServiceAccount (with IRSA)..."
kubectl apply -f k8s/base/serviceaccount.yaml

echo ""
echo "4. Creating ConfigMap..."
kubectl apply -f k8s/base/configmap.yaml

echo ""
echo "5. Creating Secrets..."
# Use create with --dry-run=client to update if exists
kubectl create secret generic attendee-secrets \
  --namespace=${NAMESPACE} \
  --from-literal=DJANGO_SECRET_KEY="${DJANGO_SECRET_KEY}" \
  --from-literal=CREDENTIALS_ENCRYPTION_KEY="${CREDENTIALS_ENCRYPTION_KEY}" \
  --from-literal=DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@meeting-assistant-db-north.caiw1y6ucdp6.eu-north-1.rds.amazonaws.com:5432/meeting-assistant-db-north" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "============================================"
echo "Deployment Complete!"
echo "============================================"

echo ""
echo "Verifying deployment:"
kubectl get ns ${NAMESPACE}
kubectl get serviceaccount -n ${NAMESPACE}
kubectl get configmap -n ${NAMESPACE}
kubectl get secrets -n ${NAMESPACE}

echo ""
echo "IRSA annotation:"
kubectl describe serviceaccount attendee-sa -n ${NAMESPACE} | grep eks.amazonaws.com/role-arn || echo "Warning: IRSA annotation not found"

echo ""
echo "============================================"
echo "Next steps:"
echo "1. Test bot pod creation from Django shell"
echo "2. Create a test bot: python manage.py shell"
echo "   > from bots.bot_pod_creator import BotPodCreator"
echo "   > creator = BotPodCreator()"
echo "   > result = creator.create_bot_pod(bot_id=999, bot_name='test-bot')"
echo "3. Monitor pods: kubectl get pods -n ${NAMESPACE} --watch"
echo "============================================"
