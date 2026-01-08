#!/bin/sh
# Create AWS EKS token wrapper for Python Kubernetes client in /tmp (app user has write access)
cat > /tmp/aws-eks-get-token << "WRAPPER"
#!/bin/sh
exec /usr/local/bin/aws --region eu-north-1 eks get-token --cluster-name meeting-assistant-eks --output json
WRAPPER
chmod +x /tmp/aws-eks-get-token

# Execute the original command
exec "$@"
