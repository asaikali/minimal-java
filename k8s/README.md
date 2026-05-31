# k8s/

A sample Kubernetes deployment for the final image, to show the chiseled,
non-root, hardened image running under an orchestrator.

- **`deployment.yaml`** — a `Deployment` + `Service` (NodePort) running
  `minimal-java/spring-aot:local` on Docker Desktop's Kubernetes. It carries the same
  hardening as `run-spring-aot.sh` (non-root `10001:10001`, read-only root filesystem,
  all capabilities dropped, `seccompProfile: RuntimeDefault`) plus `httpGet`
  startup/readiness/liveness probes — the image has no shell for an exec health check.

```bash
./scripts/build-images.sh             # build the image locally first
kubectl apply -f k8s/deployment.yaml
curl localhost:30080                  # -> a random quote
kubectl delete -f k8s/deployment.yaml
```

It uses `imagePullPolicy: IfNotPresent` against the locally-built image (Docker
Desktop shares its containerd store with Kubernetes), so no registry is needed. See
**[Part 3 — A faster app](../docs/3-speed.md)** for the walkthrough.
