#!/bin/bash
set -e

# Kubernetes Setup Script for Attendee Bot Pods
# This script creates the necessary Kubernetes resources for running bot pods in EKS

NAMESPACE="attendee-bots"
ATTENDEE_EC2_IP="172.31.16.245"  # Update this with your EC2 attendee instance private IP

echo "Setting up Kubernetes resources for Attendee bot pods..."

# Create namespace
echo "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create service account
echo "Creating service account: attendee-sa"
kubectl create serviceaccount attendee-sa -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create secrets (you'll need to provide the actual values)
echo "Creating secrets..."
read -p "Enter AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
read -sp "Enter AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
echo ""

kubectl create secret generic attendee-secrets \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_REGION="eu-north-1" \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap with CRITICAL environment variables
echo "Creating ConfigMap with correct environment variables..."
kubectl create configmap attendee-config \
  --from-literal=DJANGO_SETTINGS_MODULE="attendee.settings.development" \
  --from-literal=POSTGRES_HOST="$ATTENDEE_EC2_IP" \
  --from-literal=DATABASE_NAME="attendee_development" \
  --from-literal=DB_HOST="$ATTENDEE_EC2_IP" \
  --from-literal=DB_PORT="5432" \
  --from-literal=REDIS_URL="redis://$ATTENDEE_EC2_IP:6379/5" \
  --from-literal=REDIS_HOST="$ATTENDEE_EC2_IP" \
  --from-literal=REDIS_PORT="6379" \
  --from-literal=AWS_RECORDING_STORAGE_BUCKET_NAME="attendee-recordings" \
  --from-literal=AWS_S3_SIGNATURE_VERSION="s3v4" \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✅ Kubernetes resources created successfully!"
echo ""
echo "Namespace: $NAMESPACE"
echo "Service Account: attendee-sa"
echo "Secret: attendee-secrets"
echo "ConfigMap: attendee-config"
echo ""
echo "IMPORTANT: The following environment variables are CRITICAL for bot pods to work:"
echo "  - DJANGO_SETTINGS_MODULE: Required for Django to load the bots app"
echo "  - POSTGRES_HOST: Required by Django settings.py (not DB_HOST)"
echo "  - REDIS_URL: Required by BotController (full URL format)"
echo ""
echo "To verify the ConfigMap was created correctly:"
echo "  kubectl get configmap attendee-config -n $NAMESPACE -o yaml"
echo ""
