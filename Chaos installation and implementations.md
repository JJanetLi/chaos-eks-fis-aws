# Pre-reqs 

1 - EKS cluster deployed 

2 - Follow below command to create app namespace and deploy application in app namespace

```
kubectl create ns app 
kubectl apply -f https://github.com/JJanetLi/chaos-eks-fis-aws/blob/app/app/retail-store-sample-app.yaml -n app
```

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

## Litmus chaos experiment 

Pod network loss is chosen for litmus chaos injection, pod network loss chaos injects packet loss by starting a traffic control (tc) process with netem rules to add egress loss , it can test the application's resilience to lossy/flaky network. 

Step1: Deploy the pod-network-loss experiment resource in the designed namespace 

```
kubectl apply -f 'https://hub.litmuschaos.io/api/chaos/master?file=faults/kubernetes/pod-network-loss/fault.yaml' -n app 
```

Expected outcome: 
```
chaosexperiment.litmuschaos.io/pod-network-loss created
```
Step 2: Deploy required permissions (RBAC) for above chaos injection 

Save below file as pod-network-loss-rbac.yaml, make sure to replace the namespace value to the destinated namespace where pods deployed 
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-network-loss-sa
  namespace: app
  labels:
    name: pod-network-loss-sa
    app.kubernetes.io/part-of: litmus
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-network-loss-sa
  namespace: app
  labels:
    name: pod-network-loss-sa
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
  name: pod-network-loss-sa
  namespace: app
  labels:
    name: pod-network-loss-sa
    app.kubernetes.io/part-of: litmus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-network-loss-sa
subjects:
- kind: ServiceAccount
  name: pod-network-loss-sa
  namespace: app
```

Run below command 
```
kubectl apply -f pod-network-loss-rbac.yaml
```

Expected outcome 
```
serviceaccount/pod-network-loss-sa created
role.rbac.authorization.k8s.io/pod-network-loss-sa created
rolebinding.rbac.authorization.k8s.io/pod-network-loss-sa created
```

Step3: Create experiment configuration into a yaml file, with name pod-network-loss.yaml


```
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: ui-network-loss
  namespace: app 
spec:
  engineState: "active"
  annotationCheck: "false"
  appinfo:
    appns: "app"
    applabel: "app.kubernetes.io/name=ui"
    appkind: "deployment"
  chaosServiceAccount: pod-network-loss-sa
  experiments:
  - name: pod-network-loss
    spec:
      components:
        env:
        - name: NETWORK_PACKET_LOSS_PERCENTAGE
          value: '100'
        - name: TARGET_PODS
          value: 'ui-d6bddf848-br4qt'
        - name: TOTAL_CHAOS_DURATION
          value: '60'
```

Step 4 Validate chaos injection 

A: Validate from pod-network-loss pod log in app namespace 

```
kubectl get pods -n app | grep loss 
pod-network-loss-7dsh6a-kzmtg     0/1     Completed   0              3m29s
ui-network-loss-runner            0/1     Completed   0              3m31s
kubectl logs -n app -f pod-network-loss-7dsh6a-kzmtg
```

Expected outcome: 

```
time="2024-06-19T10:55:51Z" level=info msg="Experiment Name: pod-network-loss"
time="2024-06-19T10:55:51Z" level=info msg="[PreReq]: Getting the ENV for the pod-network-loss experiment"
time="2024-06-19T10:55:53Z" level=info msg="[PreReq]: Updating the chaos result of pod-network-loss experiment (SOT)"
time="2024-06-19T10:55:57Z" level=info msg="The application information is as follows\n" Loss Percentage=100 Targets= Target Container= Chaos Duration=60 Container Runtime=containerd
time="2024-06-19T10:55:57Z" level=info msg="[Info]: The chaos tunables are:" PodsAffectedPerc=0 NetworkPacketLossPercentage=100 Sequence=parallel
time="2024-06-19T10:55:57Z" level=info msg="[Chaos]:Number of pods targeted: 1"
time="2024-06-19T10:55:57Z" level=info msg="Target pods list for chaos, [ui-d6bddf848-br4qt]"
time="2024-06-19T10:55:57Z" level=info msg="[Status]: Checking the status of the helper pods"
time="2024-06-19T10:56:02Z" level=info msg="pod-network-loss-helper-nl5mb helper pod is in Running state"
time="2024-06-19T10:56:04Z" level=info msg="[Wait]: waiting till the completion of the helper pod"
time="2024-06-19T10:56:04Z" level=info msg="helper pod status: Running"
...
time="2024-06-19T10:57:05Z" level=info msg="[Confirmation]: pod-network-loss chaos has been injected successfully"
```
B: Validate from network testing from a different pod using telnet tool

Use below command to get ui pod IP

```
kubectl get pods -n app -o wide | grep ui
ui-d6bddf848-br4qt                1/1     Running   0             73m   172.31.39.211   ip-172-31-47-5.ec2.internal   <none>           <none>
```

Before chaos injection 
```
telnet 172.31.39.211 8080
Connected to 172.31.39.211
```

During chaos injection, disconnection is expected 
```
telnet 172.31.39.211 8080

telnet: can't connect to remote host (172.31.39.211): Host is unreachable
```
