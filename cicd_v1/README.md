# CI/CD Impelementation
This demo will walk through setting up a CI/CD pipeline that uses the following:
- DockerHub / GitHub
- Jenkins
- Spinnaker
- AWS
- EKS


### Install Pre-Requisites

#### Kubectl

#### Eksctl

#### Helm

#### Jenkins
yum update -y
yum install docker
service docker start
systemctl status docker
usermod -aG docker ec2-user
docker image pull jenkins/jenkins:lts
docker container run -d -p 8082:8080 --name jenkins jenkins/jenkins:lts
docker exec -it jenkins /bin/bash
cat /var/jenkins_home/secrets/initialAdminPassword

Install the Docker and ECR plugins.

Access:
http://<IP>:8082

In the instance:
docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword


### Setup the Pipeline

High-level steps:
- Create the EKS Cluster.
- Deploy Jenkins.
- Build your sample app.
- Install Spinnaker and expose it.
- Add GitHub account to Spinnaker.
- Configure ECR to store images pushed by Jenkins.
- Configure Jenkins to build/push Docker images.
- Build the CD Spinnaker pipeline.
- Run the pipeline and deploy the app.
- Cleanup.


#### Create the EKS Cluster
`eksctl create cluster -f eks-cluster.yml`


#### Deploy Jenkins
```
cd cicd_v1
terraform init
terraform apply
```

Within the instance:
`docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword`


#### Build the App/microservice
`Git clone https://github.com/aws-samples/sample-microservice-with-spinnaker.git`


#### Install Spinnaker into EKS Cluster
```
sudo update-halyard
MY_K8_ACCOUNT="kag-eks-cluster"
hal config provider kubernetes enable
hal config provider kubernetes account add ${MY_K8_ACCOUNT} --provider-version v2 --context $(kubectl config current-context)
hal config features edit --artifacts true
hal config deploy edit --type distributed --account-name $MY_K8_ACCOUNT
hal config storage s3 edit \
    --access-key-id $AKIAZI54RDU2ZV7FUZ33 \
    --secret-access-key \
    --region us-west-1
hal config storage edit --type s3
hal config version edit --version 1.26.3
hal deploy apply

export NAMESPACE=spinnaker
kubectl -n ${NAMESPACE} expose service spin-gate --type LoadBalancer \
 --port 80 \
 --target-port 8084 \
 --name spin-gate-public
kubectl -n ${NAMESPACE} expose service spin-deck --type LoadBalancer \
 --port 80 \
 --target-port 9000 \
 --name spin-deck-public

 export API_URL=$(kubectl -n $NAMESPACE get svc spin-gate-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
 export UI_URL=$(kubectl -n $NAMESPACE get svc spin-deck-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

 hal config security api edit --override-base-url http://${API_URL}
 hal config security ui edit --override-base-url http://${UI_URL}
 hal deploy apply
```

Get the Deck's URL and connect to it:
```
kubectl get svc spin-deck-public -n spinnaker
hal deploy connect
```


#### Add GitHub Account to Spinnaker
```
hal config artifact github account add kabirg
hal deploy apply
```


#### Configure ECR to store images pushed by Jenkins.
ECR > Repositories > Create Repo >
-  Create a public repo call `kag-sample-microservice`


#### Configure Jenkins to build/push Docker images.
Jenkins > New Item > Freestyle Project >
- Call it `kag-sample-microservice-job`
- 




#### Build the CD Spinnaker pipeline.
#### Run the pipeline and deploy the app.


#### Cleanup
```
hal deploy clean
kubectl delete ns spinnaker --grace-period=0
eksctl delete cluster -f eks-cluster.yml
terraform destroy
```

### Sources

- https://aws.amazon.com/blogs/opensource/deployment-pipeline-spinnaker-kubernetes/
