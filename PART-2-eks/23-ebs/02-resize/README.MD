# Check the SC manifest

Using `allowVolumeExpansion`: true # Default: false

# Apply

kubectl apply -f manifests

# Edit pvc to increase volume size

Change `4Gi` to `5Gi`

kubectl apply -f manifests

You can see the volume changed on console and cli

kubectl get pv

```
# Notes:
1 - You can only increase volume. Cannot decrease.
2 - You may need to wait 6 hours to change volume again.
```
