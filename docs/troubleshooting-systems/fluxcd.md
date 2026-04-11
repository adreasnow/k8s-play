# FluxCD

If FluxCD is having issues check the logs for details:

For Helm issues:

```bash
kubectl logs -n flux-system <helm-controller pod name>
```

For Kustomize issues:

```bash
kubectl logs -n flux-system <kustomize-controller pod name>
```
