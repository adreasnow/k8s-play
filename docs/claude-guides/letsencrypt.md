# cert-manager + Let's Encrypt for Traefik on EKS Auto Mode

Free, auto-renewed TLS certificates without ACM or NLB TLS termination.

---

## 1. Install cert-manager via Helm

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set crds.enabled=true \
  --set resources.requests.cpu=50m \
  --set resources.requests.memory=128Mi
```

## 2. Create a Let's Encrypt ClusterIssuer

```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      # Use DNS-01 via Route53 — works behind NLB TCP passthrough
      # without needing HTTP-01 ingress challenges
      - dns01:
          route53:
            region: ap-southeast-2 # Your region
            # If using IRSA/Pod Identity (recommended):
            # auth:
            #   kubernetes:
            #     serviceAccountRef:
            #       name: cert-manager
      # OR use HTTP-01 if you prefer (requires port 80 reachable):
      # - http01:
      #     gatewayHTTPRoute:
      #       parentRefs:
      #         - name: traefik
      #           namespace: traefik
      #           sectionName: web
```

```bash
kubectl apply -f cluster-issuer.yaml
```

### DNS-01 vs HTTP-01

**DNS-01 (recommended):** cert-manager creates a TXT record in Route53 to prove domain ownership. Works for wildcards, doesn't need port 80 open, and doesn't depend on your ingress being healthy. Requires IAM permissions for Route53.

**HTTP-01:** cert-manager serves a challenge token via your Gateway on port 80. Simpler IAM setup but can't issue wildcard certs and requires your ingress path to be fully working first.

## 3. IAM permissions for DNS-01 (Route53)

Create a policy and attach it to cert-manager's service account via EKS Pod Identity:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/YOUR_ZONE_ID"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ListHostedZonesByName",
      "Resource": "*"
    }
  ]
}
```

Associate via EKS Pod Identity:

```bash
aws eks create-pod-identity-association \
  --cluster-name your-cluster \
  --namespace cert-manager \
  --service-account cert-manager \
  --role-arn arn:aws:iam::YOUR_ACCOUNT:role/cert-manager-route53
```

## 4. Request a certificate

### Option A: Wildcard cert (one cert for all subdomains)

```yaml
# wildcard-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
  namespace: traefik # Must match Gateway's namespace
spec:
  secretName: my-wildcard-cert # Referenced by gateway.listeners.websecure
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "example.com"
    - "*.example.com"
```

```bash
kubectl apply -f wildcard-cert.yaml
```

### Option B: Per-domain certs

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-cert
  namespace: traefik
spec:
  secretName: app-example-com-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "app.example.com"
```

Then update your Gateway listener to reference the specific secret:

```yaml
certificateRefs:
  - kind: Secret
    name: app-example-com-tls
    group: ""
```

## 5. Verify it's working

```bash
# Check certificate status
kubectl get certificate -n traefik
# Should show READY=True

# Check the secret was created
kubectl get secret my-wildcard-cert -n traefik

# Check for issues
kubectl describe certificate wildcard-cert -n traefik
kubectl describe certificaterequest -n traefik
kubectl describe order -n traefik

# Test TLS
curl -v https://app.example.com
```

## 6. How renewal works

cert-manager automatically renews certificates 30 days before expiry. Let's Encrypt certs are valid for 90 days, so renewal happens roughly every 60 days. No manual intervention, no cron jobs, no Lambda functions — genuinely set and forget.

The renewed certificate is written to the same Secret, and Traefik picks it up automatically via its Kubernetes provider watch.

## Troubleshooting

**Certificate stuck on `Issuing`:** Check the Order and Challenge resources. For DNS-01, the most common issue is IAM permissions — cert-manager needs `route53:ChangeResourceRecordSets` on your hosted zone.

**Secret not appearing in traefik namespace:** The Certificate resource must be created in the same namespace as your Gateway (typically `traefik`).

**Let's Encrypt rate limits during testing:** Use the staging server first:

```yaml
server: https://acme-staging-v02.api.letsencrypt.org/directory
```

Switch to prod once everything works. Staging certs aren't trusted by browsers but have much higher rate limits.
