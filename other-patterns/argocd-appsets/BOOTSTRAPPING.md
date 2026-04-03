# Bootstrapping

1. Create a k8s cluster
2. Install ArgoCD

```bash
helm upgrade --install \
--repo https://argoproj.github.io/argo-helm \
--namespace argocd \
--create-namespace \
argocd argo-cd
```

4. Apply the Root manifest

```bash
kubectl apply -f argocd-appsets/bootstrap/root-app.yaml
```

5. Log in with `admin`
   - To get admin password -

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

If your repo is private:

1. Create an SSH key for your repo

```bash
ssh-keygen -t ed25519 -C "ArgoCD Deploy Key" -N "" -f ./deploy-key
gh repo deploy-key add ./deploy-key.pub --title "ArgoCD Deploy Key"
```

2. Add your repo to ArgoCD and add the private key contents from `./deploy-key`
