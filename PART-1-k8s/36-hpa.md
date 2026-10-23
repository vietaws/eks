# HorizontalPodAutoscaler

**Learning objective:** autoscale a Deployment's replicas based on CPU load.

"Traffic doubles at noon and drops at night. Manually scaling is a losing game.

The HorizontalPodAutoscaler watches CPU and adds or removes replicas for you.

Let's watch it react to real load."

## Demo

1. "Deploy the CPU-burnable app, its Service, and the HPA (target 50% CPU, 1–5 replicas)."
   ```bash
   cat 00-manifests/php-apache.yaml
   kubectl apply -f 00-manifests/php-apache.yaml
   kubectl rollout status deploy/php-apache
   kubectl get hpa php-apache
   ```
   Expected: HPA shows `cpu: <low>%/50%`, REPLICAS 1.

2. "Generate load — a Pod hammering the Service in a loop."
   ```bash
   kubectl run load --image=busybox:1.36 --restart=Never -- \
     /bin/sh -c "while true; do wget -q -O- http://php-apache; done"
   ```
   Expected: load starts; CPU climbs over the next ~30s.

3. "Watch the HPA react — replicas scale up."
   ```bash
   kubectl get hpa php-apache -w
   # (in another pane) kubectl get deploy php-apache -w
   ```
   Expected: CPU shoots well above 50% (often 400%+); REPLICAS climbs toward 5.

4. "Stop the load and it scales back down (after a cooldown)."
   ```bash
   kubectl delete pod load --force --grace-period=0
   # replicas return to 1 after the stabilization window (a few minutes)
   ```
   Expected: CPU drops; replicas eventually return to 1.

5. "Clean up."
   ```bash
   kubectl delete -f 00-manifests/php-apache.yaml
   ```

**✅ Conclusions:**

- HPA scales replicas to hold a target metric (CPU % of request).
- Needs metrics-server; requests must be set for % to mean anything.
- Scale-up is quick; scale-down waits a stabilization window.
- That's self-healing + autoscaling — the resilience toolkit.