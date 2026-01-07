#!/bin/bash
set -euo pipefail

# Usage: ./build-and-push.sh <aws-profile> [image-tag]
# Example: ./build-and-push.sh reply v1.0.0

if [ $# -lt 1 ]; then
    echo "Error: AWS profile is required"
    echo "Usage: $0 <aws-profile> [image-tag]"
    echo "Example: $0 reply v1.0.0"
    exit 1
fi

AWS_PROFILE="$1"
IMAGE_TAG="${2:-latest}"
AWS_REGION="eu-north-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --query Account --output text)
ECR_REPOSITORY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/attendee"

echo "============================================"
echo "Building attendee image with profile: ${AWS_PROFILE}"
echo "Image tag: ${IMAGE_TAG}"
echo "ECR Repository: ${ECR_REPOSITORY}"
echo "============================================"

cd "$(dirname "$0")/.."

echo ""
echo "Building Docker image..."
docker build --platform linux/amd64 -t attendee:${IMAGE_TAG} .

echo ""
echo "Authenticating to ECR..."
aws ecr get-login-password --region ${AWS_REGION} --profile ${AWS_PROFILE} | \
  docker login --username AWS --password-stdin ${ECR_REPOSITORY}

echo ""
echo "Tagging images..."
docker tag attendee:${IMAGE_TAG} ${ECR_REPOSITORY}:${IMAGE_TAG}
docker tag attendee:${IMAGE_TAG} ${ECR_REPOSITORY}:latest

echo ""
echo "Pushing images to ECR..."
docker push ${ECR_REPOSITORY}:${IMAGE_TAG}
docker push ${ECR_REPOSITORY}:latest

echo ""
echo "============================================"
echo "✓ Image pushed: ${ECR_REPOSITORY}:${IMAGE_TAG}"
echo "✓ Image pushed: ${ECR_REPOSITORY}:latest"
echo "============================================"
