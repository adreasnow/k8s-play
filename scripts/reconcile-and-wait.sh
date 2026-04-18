#!/bin/bash
set -euo pipefail

TIMEOUT=600  # 10 minutes total
INTERVAL=10  # poll every 10s
elapsed=0

# 1. Trigger the source refresh + top-level reconcile
flux reconcile kustomization flux-system --with-source --timeout=5m

# 2. Poll until all Kustomizations are Ready
while [ $elapsed -lt $TIMEOUT ]; do
  not_ready=$(flux get ks -A --no-header 2>/dev/null | awk '$5 != "True"' | wc -l | tr -d ' ')

  if [ "$not_ready" -eq 0 ]; then
    echo "✅ All Kustomizations are Ready!"
    flux get ks -A
    exit 0
  fi

  echo "⏳ Waiting for $not_ready Kustomization(s) to become Ready..."
  flux get ks -A --status-selector ready=false
  sleep $INTERVAL
  elapsed=$((elapsed + INTERVAL))
done

echo "❌ Timeout waiting for Kustomizations to become Ready"
flux get ks -A
exit 1
