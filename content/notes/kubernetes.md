---
title: "K8s and the 😶‍🌫️"
date: 2025-02-05T06:43:40+01:00
draft: true
---

k8s manages and orchestrates clusters of containerised applications, 
by abstracting over pools of computing resources cpu, network, memory & disk. and abstracting deploying to a public cloud(s).
via declarative yaml, json (but also [imperative apis](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-command/))

```sh
desired <-> observed <-> reconciliation
```

intuition/basic algorithm: https://en.wikipedia.org/wiki/Bin_packing_problem

hypervisors: https://pages.cs.wisc.edu/~remzi/OSTEP/vmm-intro.pdf

scheduling/orchestrating: https://fly.io/blog/carving-the-scheduler-out-of-our-orchestrator/

- supervision/fault tolerance
- scheduling
- scaling up or down
- rolling upgrades

container = OCI runtime spec (docker-engine, containerd, etc)

trace nodes and pods:
```sh
kubectl get nodes -v=9
kubectl get pods -v=9
```

local dev tooling:
```sh
tilt
minikube
kind
```

```sh
k3d cluster create <name_cluster> <flags> <image>
```

provisioning and deployment packaging:
```sh
helm
terraform
```

control plane:
api server
cloud-controller-manager
controller manager
controllers(stateless or stateful) - daemonset, statefulset, cronjobs, sidecars etc
cluster store/etcd
scheduler

services/ingress
worker nodes run workloads - (vm) - pods, attached kubelet, kube-proxy

controller - podtemplate
pods:
- labels and annotations
- restart policies
- probes
- afinity
- termination control
- security policies
- resource limits

deploying pods: manifest or controller [net, pid, mnt, UTS, IPC]
lifecyle: side car, adapter, ambassador, init

```sh
kubectl get pods <pod> -o yaml
kubectl describe pods <pod>
kubectl logs <pod>
```

```sh
kubectl exec -it <pod> -- sh #--container=<c>
```

namespaces: quotas + policies to sub-clusters of pods, services & deployments.
```sh
kubectl api-resources
kubectl get svc --namespace kube-system
kubectl config set-context --current --namespace <ns>
```

deployments: (stateless pods/container mngmt) spec + controller viz replicaset |labels + selectors| to pod,
[exposing over an external IP](https://kubernetes.io/docs/tutorials/stateless-application/expose-external-ip-address/)
```sh
kubectl get | describe deploy <deployment>
kubectl get | describe rs # at least one replica set per deploy
kubectl scale deploy <deployment> --replicas 5
kubectl rollout (status | history) | pause | resume | rollback  deploy <deployment>
```

services:


data plane

## spin up an ec2 box
https://docs.aws.amazon.com/ec2/latest/instancetypes/instance-types.html

```sh
#!/bin/bash

# exit on error
set -e
echo "Starting my ec2 box..."

# update
sudo apt-get update && sudo apt-get upgrade -y

# build and profiling
sudo apt-get install -y \
    build-essential \
    curl \
    wget \
    git \
    linux-tools-common \
    linux-tools-generic \
    linux-tools-`uname -r` \
    strace

# rs
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env

echo "Setup complete! Remember to 'source ~/.bashrc' to load the new environment variables"
```

## spin up a compute engine
https://cloud.google.com/compute/docs/instances
