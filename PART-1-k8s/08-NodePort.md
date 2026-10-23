# NodePort

**Learning objective:** expose a Service outside the cluster with NodePort.

## Demo

1. "We already have the echo backend. Add a NodePort Service on 30080."
   ```bash
   kubectl apply -f 00-manifests/vietvn-nodeport.yaml
   kubectl get svc vietvn-nodeport
   ```
   Expected: `TYPE NodePort`, `PORT(S) 80:30080/TCP`.
   The default Kubernetes NodePort range is `30000–32767`

2. "Find a node's internal IP."
   ```bash
   kubectl get nodes -o wide
   NODEIP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[?(@.type=="InternalIP")].address}')
   echo $NODEIP
   ```
   Expected: a `172.18.x.x` address (the kind node container IP).

3. "Reach it from a Pod using node-ip:30080 (works from inside the Docker network)."
   ```bash
   kubectl run npjob --image=curlimages/curl:8.11.1 --restart=Never -i --rm -- \
     curl -s "http://$NODEIP:30080"
   ```
   Expected: `hello from echo-...`.
   Note (kind): from your Mac/Windows host you'd map the port in kind-config or
   use `kubectl port-forward svc/echo-nodeport 8080:80`. NodePort-on-node-IP is
   most directly reachable inside the cluster's Docker network.

4. "Clean up the NodePort (keep the backend)."
   ```bash
   kubectl delete -f 00-manifests/echo-nodeport.yaml
   ```

**✅ Conclusions:**

- NodePort opens a static port on every node, on top of ClusterIP.
- Reachable at node-ip:nodePort.
- For real external traffic with a single IP, use LoadBalancer.