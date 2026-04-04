# cert-manager + Let's Encrypt for Gateway API on EKS Auto Mode

Traefik's built-in ACME does not issue certs for Gateway API listeners, so cert-manager is required.

## 1. ClusterIssuer

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
      - dns01:
          route53:
            region: ap-southeast-2
```

DNS-01 is recommended — works for wildcards, doesn't need port 80 challenges, and doesn't depend on ingress being healthy.

Use the staging server for testing: `https://acme-staging-v02.api.letsencrypt.org/directory`

## 2. IAM for Route53

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

```bash
aws eks create-pod-identity-association \
  --cluster-name your-cluster \
  --namespace cert-manager \
  --service-account cert-manager \
  --role-arn arn:aws:iam::YOUR_ACCOUNT:role/cert-manager-route53
```

## 3. Certificate

```yaml
# wildcard-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
  namespace: traefik
spec:
  secretName: my-wildcard-cert # Referenced by gateway.listeners.websecure
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "example.com"
    - "*.example.com"
```

## 4. Verify

```bash
kubectl get certificate -n traefik
# READY should be True

kubectl describe certificate wildcard-cert -n traefik
```

Renewal is automatic — cert-manager renews 30 days before the 90-day expiry. The renewed cert is written to the same Secret, and Traefik picks it up automatically.
