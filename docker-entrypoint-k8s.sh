#!/bin/sh
# Create AWS EKS token wrapper for Python Kubernetes client in /tmp (app user has write access).
#
# REQUIRES: aws-cli v2 at /usr/local/bin/aws inside the container.
# Not installed in the Dockerfile because bot pods don't need it (they use boto3
# in-process). On the EC2 attendee host this script runs as the entrypoint for
# attendee-app-local / attendee-worker-local / attendee-scheduler-local; install
# aws-cli into those containers manually after `docker compose up -d`:
#
#   for c in attendee-attendee-app-local-1 attendee-attendee-worker-local-1 attendee-attendee-scheduler-local-1; do
#     docker exec -u 0 "$c" sh -c 'apt-get update && apt-get install -y unzip && \
#       curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip && \
#       unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip'
#   done
#
# This is intentionally a runtime install rather than a Dockerfile RUN so that
# bot pod images (built from the same Dockerfile and pushed to ECR) stay lean.
cat > /tmp/aws-eks-get-token << "WRAPPER"
#!/bin/sh
exec /usr/local/bin/aws --region eu-north-1 eks get-token --cluster-name meeting-assistant-eks --output json
WRAPPER
chmod +x /tmp/aws-eks-get-token

# Execute the original command
exec "$@"
