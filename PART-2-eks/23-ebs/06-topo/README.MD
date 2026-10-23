```
# Read
- Instance supported io2 block express: https://repost.aws/knowledge-center/ebs-io1-io2-block-express-differences

c7g
c6in
m6in
m6idn
m7g
r5b
r6in
r6idn
r7g
trn1
x2idn
x2iedn

- https://aws.amazon.com/blogs/aws/amazon-ebs-io2-block-express-volumes-with-amazon-ec2-r5b-instances-are-now-generally-available/


# apply
kubectl apply -f manifest

# goto ssm session manager
sudo -i
crictl ps # check the container id for ebs-plugin
crictl logs -f ebs_plugin_container_id

# delete
kubectl delete -f manifest

# change value to decrease => FAILED
kubectl apply -f manifest
kubectl get pv

# change volume size to increase from 4 to 5 => SUCCESS
kubectl apply -f manifest
kubectl get pv

```
