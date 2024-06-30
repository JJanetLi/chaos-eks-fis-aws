# Pre-reqs 

1 - EKS cluster deployed 

2 - Follow below command to create app namespace and deploy application in app namespace

```
kubectl create ns app 
kubectl apply -f https://github.com/JJanetLi/chaos-eks-fis-aws/blob/app/app/retail-store-sample-app.yaml -n app
```
**Note - replace xxxxxx to your own AWS account number**
# Chaos Mesh 

## Installation 

Step1 -  Add chaos mesh repo to helm

```
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update
```
Step 2 - install Chaos Mesh with containerd runtime 
```yaml
helm install chaos-mesh chaos-mesh/chaos-mesh -n=chaos-mesh --set chaosDaemon.runtime=containerd --set chaosDaemon.socketPath=/run/containerd/containerd.sock --version 2.6.3 --create-namespace
```
Step 3 - Verify the installations 

```
 kubectl get pods --namespace chaos-mesh -l app.kubernetes.io/instance=chaos-mesh
```

expected output:  
```
chaos-controller-manager-86fd989fd-4qsnt   1/1     Running   0          54s
chaos-controller-manager-86fd989fd-vgls5   1/1     Running   0          54s
chaos-controller-manager-86fd989fd-zjf9p   1/1     Running   0          54s
chaos-daemon-nrnl5                         1/1     Running   0          54s
chaos-daemon-x2r4j                         1/1     Running   0          54s
chaos-dashboard-54c7d9d-2jfxt              1/1     Running   0          54s
chaos-dns-server-66d757d748-76j9g          1/1     Running   0          54s
```

## Chaos Mesh experiment 

Chaos Mesh offers a diverse range of Kubernetes chaos experiments. The Pod Kill action, for instance, simulates pod failures, allowing you to test the resilience of your applications in the face of such disruptions.

1 - Pod label can be be used to select pod target, use below command to show labels for each pod in a particular namespace 

```yaml
kubectl get pod -n app --show-labels 
```

2 - Create experiment configuration into a yaml file, with name pod-kill.yaml 
```
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-example
  namespace: chaos-mesh
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces:
      - app
    labelSelectors:
      'app.kubernetes.io/instance': 'ui'
```

3 - Trigger pod chaos injection  

Note, using kubectl to apply chaos-mesh is facing an known limit reported in github issue (https://github.com/chaos-mesh/chaos-mesh/issues/2187)

Example error: 

```
Error from server (user is forbidden on namespace app): error when creating "pod-kill.yaml": admission webhook "vauth.kb.io" denied the request: user is forbidden on namespace app
```

Proposed fix: 
```
kubectl delete validatingwebhookconfigurations.admissionregistration.k8s.io chaos-mesh-validation-auth
```

Apply pod-kill chaos 
```
kubectl apply -f pod-kill.yaml
```

Step 4 - Validate Chaos experiment 

Validate pod is being restarted: 
```
kubectl get pod -n app | grep ui
ui-d6bddf848-br4qt                1/1     Running   0             19s
```

chaos-mesh controller pod log validation for 200 chaos experiment response code: 

```
kubectl logs -l app.kubernetes.io/component=controller-manager -n chaos-mesh
```
expected logs: 

```
2024-06-19T09:33:33.992Z	DEBUG	controller-runtime.webhook.webhooks	admission/http.go:96	received request	{"webhook": "/validate-chaos-mesh-org-v1alpha1-podchaos", "UID": "13dc3c65-6038-4a66-896f-b64dcf016e88", "kind": "chaos-mesh.org/v1alpha1, Kind=PodChaos", "resource": {"group":"chaos-mesh.org","version":"v1alpha1","resource":"podchaos"}}
2024-06-19T09:33:33.992Z	INFO	PodChaos-resource	v1alpha1/zz_generated.chaosmesh.go:1715	validate create	{"name": "pod-kill-example"}
2024-06-19T09:33:33.993Z	DEBUG	controller-runtime.webhook.webhooks	admission/http.go:143	wrote response	{"webhook": "/validate-chaos-mesh-org-v1alpha1-podchaos", "code": 200, "reason": "", "UID": "13dc3c65-6038-4a66-896f-b64dcf016e88", "allowed": true}
```

# Litmus   

## Installations 


Step1 -  Add Litmus helm repo 

```
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm/
helm repo update
```
Step 2 - Install Litmus Mesh 

```yaml
helm install chaos litmuschaos/litmus --namespace=litmus --set portal.frontend.service.type=NodePort --create-namespace
```
Step 3 - Verify the installations, it takes a few mins for pod set up 

```
kubectl get pods -n litmus
```

expected output:  
```
chaos-litmus-auth-server-6db8c96466-hl5ps   1/1     Running   0          2m18s
chaos-litmus-frontend-699547f68b-xddf2      1/1     Running   0          2m18s
chaos-litmus-server-54656496c5-pt4gw        1/1     Running   0          2m18s
chaos-mongodb-0                             1/1     Running   0          2m17s
chaos-mongodb-1                             1/1     Running   0          111s
chaos-mongodb-2                             1/1     Running   0          83s
chaos-mongodb-arbiter-0                     1/1     Running   0          2m17s
```

Step 4 - Install LitmusChaos Operator where it installs all the CRDs required for litmus 

```
kubectl apply -f https://litmuschaos.github.io/litmus/litmus-operator-v1.13.8.yaml
```

Verified installation with below command and expected output 

```
kubectl get pods -n litmus  | grep ope
chaos-operator-ce-5577475cf5-rbzzh          1/1     Running   0          21s
```
# AWS Fault injection Service (FIS)

Use FIS to inject Chaos Mesh and Litmus chaos by action - aws:eks:inject-kubernetes-custom-resource

## Step 1 - Create FIS role 

The permissions required to use this action are controlled by Kubernetes using RBAC authorization.  Hence, you will need to create a FIS role and mapped into EKS access entry for RBAC permission. 

#### Step1-1: Create a trust relationship from below with name fis-role-trust-policy.json 

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": [
                  "fis.amazonaws.com"
                ]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

####  Step1-2: Create fis role with above trust relationship
```
aws iam create-role --role-name fis-role --assume-role-policy-document file://fis-role-trust-policy.json 
```

Expected outcome: 

```
{
    "Role": {
        "Path": "/",
        "RoleName": "fis-role",
        ...
        "Arn": "arn:aws:iam::account:role/fis-role",
        ...
```
## Step2 (Optional) - Create CloudWatch Log group for fault injection experiment logs

#### Step 2-1: Create cloudwatch log group: 

```
aws logs create-log-group --log-group-name fis-chaos --region us-east-1 
```

#### Step 2-2: Enable fis-role for cloudwatch related permissions, Create  below policy named fis-log.json
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CloudWatchLogsFullAccess",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogDelivery",
                "logs:PutResourcePolicy",
                "logs:DescribeResourcePolicies",
                "logs:DescribeLogGroups"
            ],
            "Resource": "*"
        }
    ]
}
```

```
aws iam create-policy --policy-name fis-log --policy-document file://fis-log.json --profile chaos
```

```
aws iam attach-role-policy --policy-arn arn:aws:iam::640480128198:policy/fis-log --role-name fis-role  --profile chaos
```

## Step 3 - Grant  FIS role EKS RBAC access

Create Access entry for fis-role: 
```
aws eks create-access-entry --cluster-name chaos-cluster --principal-arn arn:aws:iam::xxxxxx:role/fis-role --type STANDARD --username fis  --region us-east-1
```

Grant fis-role cluster admin access: 
```
aws eks associate-access-policy --cluster-name chaos-cluster  --principal-arn arn:aws:iam::xxxxxx:role/fis-role --access-scope type=cluster --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --region us-east-1
```
## Step 4 - Create FIS experiment template - Litmus Chaos 

Litmus chaos experiment of injecting http reset peer chaos will be pushed to application pod via AWS FIS. 

http reset peer chaos experiment injects http reset on the service whose port is provided as TARGET_SERVICE_PORT which stops outgoing http requests by resetting the TCP connection by starting proxy server and then redirecting the traffic through the proxy server. It can test the application's resilience to lossy/flaky http connection.

#### Step 4.1 - Install pod-http-reset-peer experiment resource in the namespace where application is deployed.

Use below command 
```
kubectl apply -f "https://hub.litmuschaos.io/api/chaos/master?file=faults/kubernetes/pod-http-reset-peer/fault.yaml" -n app
```
Verify the installation 
```
kubectl get chaosexperiments -n app | grep http
pod-http-reset-peer   6s
```

#### Step 4.2 - Grant pod-http-reset-peer chaos minimal RBAC permission

Please copy below content and save as pod-http-reset-peer-rbac.yaml, change the namespace to the namespace where application is deployed: 

```
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-http-reset-peer-sa
  namespace: app
  labels:
    name: pod-http-reset-peer-sa
    app.kubernetes.io/part-of: litmus
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-http-reset-peer-sa
  namespace: app
  labels:
    name: pod-http-reset-peer-sa
    app.kubernetes.io/part-of: litmus
rules:
  # Create and monitor the experiment & helper pods
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create","delete","get","list","patch","update", "deletecollection"]
  # Performs CRUD operations on the events inside chaosengine and chaosresult
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create","get","list","patch","update"]
  # Fetch configmaps details and mount it to the experiment pod (if specified)
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get","list",]
  # Track and get the runner, experiment, and helper pods log
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get","list","watch"]
  # for creating and managing to execute comands inside target container
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["get","list","create"]
  # deriving the parent/owner details of the pod(if parent is anyof {deployment, statefulset, daemonsets})
  - apiGroups: ["apps"]
    resources: ["deployments","statefulsets","replicasets", "daemonsets"]
    verbs: ["list","get"]
  # deriving the parent/owner details of the pod(if parent is deploymentConfig)
  - apiGroups: ["apps.openshift.io"]
    resources: ["deploymentconfigs"]
    verbs: ["list","get"]
  # deriving the parent/owner details of the pod(if parent is deploymentConfig)
  - apiGroups: [""]
    resources: ["replicationcontrollers"]
    verbs: ["get","list"]
  # deriving the parent/owner details of the pod(if parent is argo-rollouts)
  - apiGroups: ["argoproj.io"]
    resources: ["rollouts"]
    verbs: ["list","get"]
  # for configuring and monitor the experiment job by the chaos-runner pod
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create","list","get","delete","deletecollection"]
  # for creation, status polling and deletion of litmus chaos resources used within a chaos workflow
  - apiGroups: ["litmuschaos.io"]
    resources: ["chaosengines","chaosexperiments","chaosresults"]
    verbs: ["create","list","get","patch","update","delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-http-reset-peer-sa
  namespace: app
  labels:
    name: pod-http-reset-peer-sa
    app.kubernetes.io/part-of: litmus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-http-reset-peer-sa
subjects:
- kind: ServiceAccount
  name: pod-http-reset-peer-sa
  namespace: app
```

Use below command to apply 
```
kubectl apply -f pod-http-reset-peer-rbac.yaml 
```

#### Step 4.3 Create FIS experiment template 

Use below command to create FIS experiment template: 

```
aws fis create-experiment-template \
    --cli-input-json '{
        "description": "fis-litmus-chaos",
        "targets": {
                "Cluster-Target-1": {
                        "resourceType": "aws:eks:cluster",
                        "resourceArns": [
                                "arn:aws:eks:us-east-1:xxxxxx:cluster/chaos-cluster"
                        ],
                        "selectionMode": "ALL"
                }
        },
        "actions": {
                "http-reset-peer": {
                        "actionId": "aws:eks:inject-kubernetes-custom-resource",
                        "description": "litmus-http-reset-peer-chaos",
                        "parameters": {
                                "kubernetesApiVersion": "litmuschaos.io/v1alpha1",
                                "kubernetesKind": "ChaosEngine",
                                "kubernetesNamespace": "app",
                                "kubernetesSpec": "{   \"engineState\": \"active\",   \"annotationCheck\": \"false\",   \"appinfo\": {     \"appns\": \"app\",     \"applabel\": \"app.kubernetes.io/name=ui\",     \"appkind\": \"deployment\"   },   \"chaosServiceAccount\": \"pod-http-reset-peer-sa\",   \"experiments\": [     {       \"name\": \"pod-http-reset-peer\",       \"spec\": {         \"components\": {           \"env\": [             {               \"name\": \"TARGET_PODS\",               \"value\": \"ui-d6bddf848-ghr4b\"             },             {               \"name\": \"TOXICITY\",               \"value\": \"100\"             },             {               \"name\": \"TARGET_SERVICE_PORT\",               \"value\": \"8080\"             }           ]         }       }     }   ] }",
                                "maxDuration": "PT2M"
                        },
                        "targets": {
                                "Cluster": "Cluster-Target-1"
                        }
                }
        },
        "stopConditions": [
                {
                        "source": "none"
                }
        ],
        "roleArn": "arn:aws:iam::xxxxxx:role/fis-role",
        "tags": {},
        "logConfiguration": {
                "cloudWatchLogsConfiguration": {
                        "logGroupArn": "arn:aws:logs:us-east-1:xxxxxx:log-group:fis-chaos:*"
                },
                "logSchemaVersion": 2
        },
        "experimentOptions": {
                "accountTargeting": "single-account",
                "emptyTargetResolutionMode": "fail"
        }
}'
```

Record experiment template ID or query the experiment template ID 
```
aws fis list-experiment-templates --region us-east-1 | grep lit -B1
```

Expected outcome 
```
 "id": "EXT5ZByKtF4sgEL",
 "description": "fis-litmus-chaos",
```

#### Step 4.4 - Run FIS fault injections 

Verify pod connection before run the FIS experiment

Get ui pod IP 
```
kubectl get pod -n app -o wide | grep ui 
ui-d6bddf848-ghr4b                1/1     Running   2 (6d ago)    10d   172.31.38.116   ip-172-31-47-5.ec2.internal   <none>           <none>
```

Check HTTP response before Fault injection: 

```
curl -vk 172.31.38.116:8080
*   Trying 172.31.38.116:8080...
* Connected to 172.31.38.116 (172.31.38.116) port 8080
> GET / HTTP/1.1
> Host: 172.31.38.116:8080
> User-Agent: curl/8.7.1
> Accept: */*
> 
< HTTP/1.1 303 See Other
< Location: /home
< set-cookie: SESSIONID=3a7627e9-fd94-4535-be6d-80cf08f0cdb5
< content-length: 0
< 
* Request completely sent off
* Connection #0 to host 172.31.38.116 left intact
```

Run experiment: 
```
aws fis start-experiment --experiment-template-id EXT5ZByKtF4sgEL --region us-east-1
```

Output: 
```
{
    "experiment": {
        "id": "EXPpH5gti5bgNFXv1Y",
        "experimentTemplateId": "EXT5ZByKtF4sgEL",
...
```

During experiment, see the connection rest error triggered 

```
curl -vk 172.31.38.116:8080
*   Trying 172.31.38.116:8080...
* Connected to 172.31.38.116 (172.31.38.116) port 8080
> GET / HTTP/1.1
> Host: 172.31.38.116:8080
> User-Agent: curl/8.7.1
> Accept: */*
> 
* Request completely sent off
* Recv failure: Connection reset by peer
* Closing connection
curl: (56) Recv failure: Connection reset by peer
```

Verify the expriment is in completed status: 
```
aws fis get-experiment --id EXPpH5gti5bgNFXv1Y --region us-east-1 | grep status 
            "status": "completed",
                    "status": "completed",
```

