# Hands-On with Spinnaker
A demo to help Spinnaker newbie's get comfortable with it.


### Deploy Spinnaker to an EKS Cluster

Steps High-Level:
- Create the EKS Cluster1
- Install Halyard
- Setup the Cloud Provider
- Halyard Configuration Pre-Req's (Environment & Persistent Storage)
- Deploy Spinnaker


### Create the EKS Cluster
In this directory, run `eksctl create cluster -f eks-cluster.yml`


### Install Halyard on a Mac
Pre-Requisites (Java 11 is required, which requires Cask if installing on a Mac):
```
brew tap homebrew/cask-versions
brew update
brew tap homebrew/cask
brew install --cask homebrew/cask-versions/adoptopenjdk8
```

Install v11 instead:
```
brew tap adoptopenjdk/openjdk
brew install --cask adoptopenjdk11
```

Set the new version:
- View versions:\
`/usr/libexec/java_home -V`
- In Bash Profile, add the following:
```
export JAVA_8=$(/usr/libexec/java_home -v1.8)
export JAVA_11=$(/usr/libexec/java_home -v11)

 # Java 8
 #export JAVA_HOME=$JAVA_8

 # Java 11\
 export JAVA_HOME=$JAVA_11
```
- Source it:\
`source ~/.zshrc`


Install Halyard:
```
curl -O https://raw.githubusercontent.com/spinnaker/halyard/master/install/macos/InstallHalyard.sh
sudo bash InstallHalyard.sh
```

Notes:
- Version check: `hal -v`
- Update: `sudo update-halyard`
- Purge a Spinnaker deployed w/Halyard: `hal deploy clean`
- Remove Halyard: `sudo ~/.hal/uninstall.sh`


### Setup Kubernetes v2 Provider
- Add EKS "account" to Spinnaker (re: EKS cluster credentials, used by Spinnaker to deploy our apps)
```
MY_K8_ACCOUNT="kag-eks-cluster"
hal config provider kubernetes enable
hal config provider kubernetes account add ${MY_K8_ACCOUNT} --provider-version v2 --context $(kubectl config current-context)
hal config features edit --artifacts true
```


### Halyard Configuration
We need to update our Halyard config to tell it which environment do install Spinnaker. Specifically, we want to update the default (a local install) so that it does a distributed insstallation (re: installing all Spinnaker microservices independently) into a K8S cluster.

```
# This step ensures Spinnaker points the install to our remote EKS cluster, and not locally
hal config deploy edit --type distributed --account-name $MY_K8_ACCOUNT
```

We also need to configure external storage to persist our settings and pipelines.

```
hal config storage s3 edit \
    --access-key-id $AKIAZI54RDU2ZV7FUZ33 \
    --secret-access-key \
    --region us-west-1

hal config storage edit --type s3
```

### Deploy Spinnaker
```
#Update Halyard with the Spinnaker version you want to install
hal version list
hal config version edit --version 1.26.3
hal deploy apply
```

Note:
If you get any failures, try running either of the two commands below:
```
hal shutdown / hal -v
hal deploy clean
```

Verifications:
```
kubectl get svc --all-namespaces
kubectl get pods -n spinnaker -o wide
```


### Connect to Spinnaker
`hal deploy connect`

Access `localhost:9000` in your browser!


### Publicly Expose Spinnaker
The Deck (Spinnaker's UI) and Gate (Spinnaker's API Gateway), an addition to all microservices, are exposed internally within the cluster only (ClusterIP).
So we need to make a loadbalancer to expose both of them publicly.

```
export NAMESPACE=spinnaker

kubectl -n ${NAMESPACE} expose service spin-gate --type LoadBalancer \
 --port 80 \
 --target-port 8084 \
 --name spin-gate-public

kubectl -n ${NAMESPACE} expose service spin-deck --type LoadBalancer \
 --port 80 \
 --target-port 9000 \
 --name spin-deck-public
```

Now you can access the Spinnaker app from your ELB URL, but the deployment still needs to be updated so that the UI knows where the API is now located.
```
export API_URL=$(kubectl -n $NAMESPACE get svc spin-gate-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
export UI_URL=$(kubectl -n $NAMESPACE get svc spin-deck-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

hal config security api edit --override-base-url http://${API_URL}
hal config security ui edit --override-base-url http://${UI_URL}
hal deploy apply
```


### Clean Up
`hal deploy clean`\
`kubectl delete ns spinnaker --grace-period=0`\
`eksctl delete cluster -f eks-cluster.yml`


### Notes
As an alternative setup approach, you can have 3 EKS clusters (1 for Spinnaker, 2 as your target environments i.e Dev and Prod).

The following tutorial does everything we just did, but with 3 EKS clusters rather than just one:
https://aws.amazon.com/blogs/opensource/continuous-delivery-spinnaker-amazon-eks/


### TODO
Try deploying with a Helm chart instead:
https://medium.com/parkbee/spinnaker-installation-on-kubernetes-using-new-halyard-based-helm-chart-d0cc7f0b8fd0


### Sources:
- https://tecadmin.net/install-java-macos/
- https://www.bogotobogo.com/DevOps/Docker/Docker_Kubernetes_EKS_Spinnaker.php
- https://spinnaker.io/setup/install/
- https://aws.amazon.com/blogs/opensource/continuous-delivery-spinnaker-amazon-eks/
