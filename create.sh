#!/bin/bash

minikube start

flux bootstrap github \
  --owner="$(gh api user --jq '.login')" \
  --repository=fleet-infra \
  --branch=main \
  --path=./clusters/my-cluster \
  --personal
