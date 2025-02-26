---
title: "K8s and the 😶‍🌫️"
date: 2025-02-05T06:43:40+01:00
draft: true
---

k8s manages and orchestrates clusters of containerised applications, 
by abstracting over pools of computing resources cpu, network, memory & disk and abstracting deploying to a public cloud(s).
via declarative yaml, json (but also [imperative apis](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/imperative-command/))

```sh
desired <-> observed <-> reconciliation
```

- achieve high-availability while running in **fault-prone environments**
- to allow us to continuously release new versions with **zero downtime**
- to handle **dynamic workloads** (e.g. request volumes)

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

tools to observe of performance, behaviour and health of software systems: metrics, logs & traces.
tools to create/ provisioning and deployment packaging:
```sh
helm
terraform
```

control plane:

- api server
- cloud-controller-manager
- controller manager
- controllers(stateless or stateful-(stateful systems are hard!)) - daemonset, statefulset, cronjobs, sidecars etc
- cluster store/etcd
- scheduler

and worker nodes run workloads - (vm) - pods, attached kubelet, kube-proxy

controller - (podtemplate, deployment)
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
(kube-system(dns, metrics) - control plane, kube-public, kube-node-lease(heartbeat))

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

services: RESTful object - stable IP, DNS and port coupled & load-balances(endpoint slice) to pods via labels + selectors.
- internal dns lookup  (ClusterIP - internal DNS [switched fabric](https://en.wikipedia.org/wiki/Switched_fabric))
- query endpoint slices `kubectl get endpointslices`
externally via `NodePort` + `LoadBalancer`
- (NodePorts only work on high port numbers (30000-32767) and require knowledge of node names or IPs)
- cloud lb <-> `LoadBalancer`
(layer 4 via cloud controller manager <-> Service (k8s) - need layer 7(app) below to multiplex routes)

options:
- https://gateway-api.sigs.k8s.io/#what-is-the-gateway-api
- ingress: expose multiple clusterIP services <-> clould lb, routing rules etc
- service meshes(istio, linkerd - layer 7): expose multiple clusterIP services <-> clould lb, routing rules etc
- lb service: 80 || 443 - host/path deploys ingress objects

ingress:
- controller (install/setup) - parse hostnames , resolve dns routes etc
- object spec

ingress class mix and match ingress controllers (nginx, istio etc) on a cluster

```
kubectl get ing
kubectl get ingressclass
```

service discovery in a k8s cluster:
- internal DNS (coredns)
```
kubectl get pods -n kube-system -l k8s-app=kube-dns
```
- global Service kube-dns
- registry & discovery
- kube-proxy over Linux IP Virtual Server(IPVS) [deprecated - iptables]
- cluster DNS holds A and SRV records.
- local routing rules on kubelet
```
/etc/resolv.conf
```

data plane

## spin up an ec2 jumpbox

todo: https://github.com/kelseyhightower/kubernetes-the-hard-way

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


## Terraform
