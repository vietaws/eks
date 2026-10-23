# 09 — ALB HTTP → HTTPS Redirect

## 🎯 Scenario
Force all plain HTTP traffic to redirect to HTTPS at the ALB, so clients never stay on port 80.

## 🗺️ Architecture
```
Client ─HTTP:80─▶ ALB ──301 redirect──▶ HTTPS:443 (ACM cert) ──▶ Pods
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).
- An ACM certificate in `ap-southeast-1`.

## 🚀 Steps
1. Edit `manifests/05-alb.yaml`, set your cert ARN placeholder:
   ```yaml
   alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-southeast-1:ACCOUNT_ID:certificate/CERT_ID
   alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
   alb.ingress.kubernetes.io/ssl-redirect: "443"
   ```
2. Apply:
   ```bash
   kubectl apply -f ./manifests
   ```

## 🔍 Validation
```bash
# -I shows the 301 from HTTP to HTTPS
curl -I http://<alb-dns>/app1
curl -I https://<alb-dns>/app1   # 200
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
```

## 📝 Notes & cost
- `ssl-redirect: "443"` adds a redirect action on the HTTP listener — this is the one setting that turns the previous demo (08) into a redirect.
- 🔐 Use the `ACCOUNT_ID`/`CERT_ID` placeholders in the committed file.
- ALB bills per hour + LCU.
