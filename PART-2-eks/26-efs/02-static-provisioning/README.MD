# Create Security Group for EFS

```
# Get VPC ID
aws eks describe-cluster --name vietaws6 --query "cluster.resourcesVpcConfig.vpcId" --output text --profile eks
// vpc-048d412f4093ee6b6

# Get VPC CIDR
aws ec2 describe-vpcs --vpc-ids vpc-048d412f4093ee6b6 --query "Vpcs[].CidrBlock" --output text --profile eks
// 192.168.0.0/16

# Create Security Group
aws ec2 create-security-group --description efs-demo-vietaws-sg --group-name efs-sg --vpc-id vpc-048d412f4093ee6b6 --profile eks
// security group id: sg-07279a8c9186a7cc8

# Add EFS Rule
aws ec2 authorize-security-group-ingress --group-id sg-0306c8d2a3f105795 --protocol tcp --port 2049 --cidr 192.168.0.0/16 --profile eks
// Success

```

# Create EFS

## Using Console

- Go to AWS management console

- Name: `efs5`
- File System ID: `fs-0f5eecb0ee13c850b`
- Subnets: `private subnets`
- Security Group: `efs-sg` - NodeGroup

✅ Check Open EFS Port (2049) for neccessary Worker Nodes or Fargate if any

# Create EFS PV

```
# Verify
kubectl get pv,pvc,pods
=> Output: There is no pv, pvc

# Command
kubectl apply -f manifests/01-efs-pv.yaml
=> Output: persistentvolume/efs-pv created

# Check PV
kubectl get pv

NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
efs-pv   5Gi        RWO            Retain           Available                          <unset>                          30s

=> Status: Available
```

The `PV` status is `Available`, but it is not yet `bound` with any `PVC`. Next,
we create the persistent volume claim (`PVC`)

# Create EFS PVC

```
# Verify before doing
kubectl get pv,pvc

# Create PVC
kubectl apply -f manifests/02-efs-pvc.yaml
// Output: persistentvolumeclaim/efs-claim created

# Verify PV
kubectl get pv

NAME     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM               STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
efs-pv   5Gi        RWO            Retain           Bound    default/efs-claim                  <unset>                          3m35s

# Verify PVC
kubectl get pvc

NAME        STATUS   VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
efs-claim   Bound    efs-pv   5Gi        RWO                           <unset>                 56s

PV Status: Bound
Capacity: 5Gi
```

# Deploy Single App - Static Provisioning

```
# Command
kubectl apply -f manifests/03-app.yaml

# Verify
kubectl exec -ti efs-app -- tail -f /data/out.txt

// Output
Wed May 29 04:30:57 UTC 2024
Wed May 29 04:30:59 UTC 2024
Wed May 29 04:31:01 UTC 2024
Wed May 29 04:31:03 UTC 2024
Wed May 29 04:31:05 UTC 2024
Wed May 29 04:31:07 UTC 2024

# Timezone
date -u # UTC

TZ='Asia/Ho_Chi_Minh' date

https://linuxize.com/post/how-to-set-or-change-timezone-in-linux/

Ref 📗: https://aws.amazon.com/blogs/storage/persistent-storage-for-kubernetes/

# Check file size EFS

aws efs describe-file-systems \
    --file-system-id fs-0f5eecb0ee13c850b --profile eks

```

# Explore EFS

```
# Exec pods/efs-app
kubectl exec -it pods/efs-app -- sh

# switch Root
su

# Check storage size
df -BG

Filesystem       1G-blocks  Used   Available Use% Mounted on
overlay                20G    9G         12G  42% /
tmpfs                   1G    0G          1G   0% /dev
tmpfs                   2G    0G          2G   0% /sys/fs/cgroup
127.0.0.1:/    8589934592G    0G 8589934592G   0% /data
/dev/nvme0n1p1         20G    9G         12G  42% /etc/hosts
shm                     1G    0G          1G   0% /dev/shm
tmpfs                   4G    1G          4G   1% /run/secrets/kubernetes.io/serviceaccount
tmpfs                   2G    0G          2G   0% /proc/acpi
tmpfs                   2G    0G          2G   0% /sys/firmware

// You can see /data (EFS vollume) has 8589934592G

# Check size /data
cd /data
du -sh
ls -lh

# Check size via SSM on EC2 Node
sudo -i
df -BG | grep efs

```
