- NodePools can be configured for a mix of On- Demand and Spot (Spot is
  prioritized) • Karpenter has built-in Spot interruption h

- Karpenter has built-in Spot interruption handler

## Spot Notification

- 2-minute Spot Instance interruption notice via Amazon EventBridge event

- Set as environment variables in Karpenter controller Deployment object

## Priority of picking instance

1. Spot

- Balance between cost and probability of interruption

- Lowest cost but small capacity pool is not desirable

2. On-demand

- Lowest price
