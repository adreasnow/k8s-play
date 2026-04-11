# Creating a local K8s cluster

You'll need a k8s cluster to be able to make this work, and it will need network access to GitHub. You will need to have be able to connect to the cluster locally with kubectl.

## [OrbStack](https://orbstack.dev) **Recommended**

Better, faster, lighter, less corporate docker-compatible container runtime thatn Docker.

Internally it creates a containerised instance of the k3s cluster from Rancher, and provides all the modern conveniences while still leaving plenty of room to build/play in.

This will also give you good visibility of your pods via the UI and will give you namespace networking access to all pods and services for debugging.

Domain = `k8s.orb.local`

- Start - `orb start k8s`
- Stop - `orb stop k8s`
- Destroy - `orb delete k8s -a`
- Reset OrbStack - `orb reset`
  - This will purge all contianers, caches, volumes etc. from orbstack. Not jsut K8s.
