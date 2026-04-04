# Check PreferClose is being honoured

kubectl get endpointslices -n my-app -o yaml | grep -A2 "hints"

# Verify topology labels on nodes

kubectl get nodes -L topology.kubernetes.io/zone

# Verify pods are spread evenly

kubectl get pods -n my-app -o wide

# Monitor cross-AZ bytes with VPC Flow Logs

# Filter by source/dest AZ in Athena or CloudWatch Insights
