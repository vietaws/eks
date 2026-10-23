# HPA vs Karpenter

HPA (Horizontal Pod Autoscaler) - monitor metrics (cpu, ram, disk) on Deployment
and scale if reach

eg: if Pod >= 50% => scale more pod If there is no available resourceon Node =>
Pod will be pending (unschedule)

=> in this situation, by default we have to provision new EC2 or use Cluster
Autoscaler (CA) to increase Node in the Manged Node Group.

The disadvantages of this approach: we have to create many managed node group
for different variants such as: compute node group, memory node group, gpu node
group or node group by tenant.

## problem with Node AutoScaler - Node provision latency

Pending schedule pods => Cluster Autoscaler (CA) => Update Auto Scaling Group on
Amazon EC2 => Using EC2 API => Increase EC2

This process takes minutes to start

With Karpenter:

Pending schedule pods => Using EC2 API => Increase EC2

# What is Karpenter?

- Efficient Node Autoscaler for Kubernetes

- Automatic launch Node without using NodeGroup

- Created by AWS

- Open sourced
  - AWS donated to CNCF
  - Adopted by Azure

# Benefits of Karpenter

- Cost Optimization

- Kubernetes native

- Support diverse workload (ML & AI)

- Help upgrade & Patching

# HPA vs Karpenter

- HPA helps to `Scale Pod`. Karpenter helps to `Scale Node`

- HPA triggered by Pod metrics such as: CPU, memory, or custom metrics.
  Karpenter is triggered by pending scheduling Pod

- HPA is part of Kubernetes distribution. Karpenter needs to be installed
