# 08 — ALB with HTTPS (ACM Certificate)

## 🎯 Scenario
Terminate **TLS on the ALB** using a certificate from AWS Certificate Manager (ACM). The ALB listens on 443 (and 80) and forwards to your pods.

## 🗺️ Architecture
```
Client ──HTTPS:443──▶ ALB (ACM cert) ──HTTP──▶ target group ──▶ Pods
Client ──HTTP:80 ───▶ ALB
```

## ✅ Prerequisites
- AWS Load Balancer Controller installed (`06-alb`).
- An **ACM certificate** in `ap-southeast-1` for your domain.

## 🚀 Steps
1. Request/validate an ACM cert for your domain (DNS validation is easiest).
2. Edit `manifests/05-alb.yaml` and set the certificate ARN placeholder:
   ```yaml
   alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-southeast-1:ACCOUNT_ID:certificate/CERT_ID
   ```
   > ⚠️ Use **your own** ARN. Never commit a real account ID / cert ARN.
3. Apply:
   ```bash
   kubectl apply -f ./manifests
   ```

## 🔍 Validation
```bash
kubectl get ingress -w
curl -I https://<alb-dns-or-your-domain>/app1   # expect HTTP/2 200
```

## 🧹 Cleanup
```bash
kubectl delete -f ./manifests
```

## 📝 Notes & cost
- The ALB can auto-discover the cert from the host rules if you omit
  `certificate-arn`, but explicit is clearer for a demo.
- ALB bills per hour + LCU. The ACM cert itself is free.
- 🔐 **Security:** the committed manifest must use the `ACCOUNT_ID`/`CERT_ID`
  placeholders — do not hardcode a real ARN.
