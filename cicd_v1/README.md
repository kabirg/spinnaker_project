# CI/CD Impelementation
This demo will walk through setting up a CI/CD pipeline that uses the following:
- DockerHub / GitHub
- Jenkins
- Spinnaker
- AWS
- EKS


### Install Pre-Requisites
- Kubectl
- Eksctl
- Helm


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

Notes:
- Add `S3FullAccess` to the NodeGroup IAM Policy (to allow Front50 to communicate with S3).
- Add `AmazonEC2ContainerRegistryFullAccess` to the NodeGroup IAM Policy to allow pushing to ECR.


#### Deploy/Setup Jenkins
```
cd cicd_v1
terraform init
terraform apply
```

Within the Instance:\
`docker exec -it jenkins cat /var/jenkins_home/secrets/initialAdminPassword`

Access the URL:\
`http://[JENKINS_IP]:8082`

Install the Docker and ECR plugins.


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

Validate that everything is working:\
`kubectl get po -n spinnaker -o wide`

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


#### Create ECR Repo & Configure for Access from Spinnaker/EKS
Configure ECR and EKS:
- ECR > Repositories > Create Repo > Create a private repo called `kag-sample-microservice`.
- On the EKS Worker Node IAM role, add the `AmazonEC2ContainerRegistryFullAccess` policy (to allow EKS access to ECR).

Configure Spinnaker to integrate w/ECR:
- Grab the Registry URL:\
`aws ecr describe-repositories --region us-east-1 | grep Uri`
- Enable the Docker Registry provider:\
`hal config provider docker-registry enable`
- Add the account (we use the `--password-command` option so that Halyard can grab the credentials from the ECR token using AWSCLI):

```
ADDRESS=[ECR_REGISTRY_URL]
REGION=us-east-1

hal config provider docker-registry account add my-ecr-registry \
 --address $ADDRESS \
 --username AWS \
 --password-command "aws --region $REGION ecr get-authorization-token --output text --query 'authorizationData[].authorizationToken' | base64 -d | sed 's/^AWS://'"

hal deploy apply
```


#### Configure Jenkins to build/push Docker images.
Jenkins > New Item > Freestyle Project >
- Call it `kag-sample-microservice-job`

Now we need to configure the job. This includes setting up the webhook and build trigger, and configuring the build phase of the job.

##### Setup a Webhook
This needs to be configured from the client (GitHub) and server (Jenkins) perspective.

**GitHub**
- Go to project (https://github.com/kabirg/spinnaker_project)
- Settings > Webhooks > Add Webhook
  - Payload URL: `[JENKINS_URL]/github-webhook/`
  - Content Type: `application/json`
  - Which event to trigger webhook: `Just the push event`
  - Active: `Checked`
  - Add Webhook.

**Jenkins**
- In the Job config, add `https://github.com/kabirg/spinnaker_project.git` to the `Git` section under the `Source Code Management` tab.
- Check off `GitHub hook trigger for GITScm polling` in the **Build Triggers** section.

Src: https://www.blazemeter.com/blog/how-to-integrate-your-github-repository-to-your-jenkins-project

##### Configure Build Phase
In the Jenkins job config:
- Build > Add a Build Step > Build/Publish Docker Image
  - Directory for Dockerfile: `sample-microservice-with-spinnaker/`
  - Cloud: `Docker`
  - Image (BUILD_NUMBER is a Jenkins system-variable):
  ```
  637661158709.dkr.ecr.us-east-1.amazonaws.com/kag-sample-microservice
  637661158709.dkr.ecr.us-east-1.amazonaws.com/kag-sample-microservice:v${BUILD_NUMBER}
  ```
  - Check off:\
    `Push Images`\
    `Clean Local Images`\
    `Attempt to remove images when jenkins deletes the run`
  - Registry Credentials > Add > Jenkins > AWS Credentials > input IAM credentials > select ECR registry (behind the scenes, the ECR plugin is using your IAM creds to do the ECR authentication).
  - Save.


#### Build the CD Spinnaker pipeline.
Here we'll do the following:
- Create the Spinnaker app.
- Create the Spinnaker pipeline.
- Setup artifacts (base and override Helm templates to deploy our app into EKS, and the Docker image).
- Setup pipeline trigger.
- Create the pipeline stages (bake and deploy).

##### Create the Spinnaker app.
Only name and email are required params.

##### Create the Spinnaker pipeline.
In the app > Pipelines > Configure New Pipeline.

Setup the Automated Trigger
*We'll configure the pipeline so that it's triggered by a push of a new image to ECR*
- Type: Docker Registry


##### Setup artifacts (base and override Helm templates to deploy our app into EKS, and the Docker image).
##### Setup pipeline trigger.
##### Create the pipeline stages (bake and deploy).





#### Run the pipeline and deploy the app.


#### Cleanup
```
hal deploy clean
kubectl delete ns spinnaker --grace-period=0
# Remove 'AmazonEC2ContainerRegistryFullAccess' and 'S3FullAccess' from NodeGroup IAM Role
eksctl delete cluster -f eks-cluster.yml
terraform destroy
# Remove Webhook from GitHub project.
# Delete the ECR repo.
```

### Sources

- https://aws.amazon.com/blogs/opensource/deployment-pipeline-spinnaker-kubernetes/
