# apply

kubectl apply -f manifest

# goto ssm session manager

sudo -i crictl ps

# check the container id for ebs-plugin

crictl logs -f <ebs_plugin_container_id>

# Check Pod IP

kubectl get pod --all-namespaces -o json | jq '.items[] | .spec.nodeName + " " +
.status.podIP' | grep ip-192-168-124-198.ap-southeast-1.compute.internal | wc

# delete

kubectl delete -f manifest

# change value to decrease => FAILED

kubectl apply -f manifest kubectl get pv

# change volume size to increase from 4 to 5 => SUCCESS

kubectl apply -f manifest kubectl get pv
