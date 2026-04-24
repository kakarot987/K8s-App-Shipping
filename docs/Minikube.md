Minikube is a tool that enables local Kubernetes development by setting up a single-node cluster on macOS, Linux, and Windows.

Minikube installation Steps: (Here)[!https://minikube.sigs.k8s.io/docs/start/?arch=%2Flinux%2Fx86-64%2Fstable%2Fbinary+download]

#### kubectl
The Kubernetes command-line tool, kubectl, allows you to run commands against Kubernetes clusters. You can use kubectl to deploy applications, inspect and manage cluster resources, and view logs.
Guide to install Kubectl: https://kubernetes.io/docs/tasks/tools/

##### Create a minikube cluster
```minikube start```

##### Check the status of the minikube cluster
Verify the status of the minikube cluster to ensure all the components are in a running state.  

```minikube status```  

The output from the above command should show all components Running or Configured:  

```
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

##### Open the Dashboard
Open a new terminal, and run:  
```
# Start a new terminal, and leave this running.
minikube dashboard
```  
Now, switch back to the terminal where you ran minikube start.
NOTE: The dashboard command enables the dashboard add-on and opens the proxy in the default web browser. You can create Kubernetes resources on the dashboard such as Deployment and Service.

##### Create a Deployment
A Kubernetes Pod is a group of one or more Containers, tied together for the purposes of administration and networking. The Pod in this tutorial has only one Container. A Kubernetes Deployment checks on the health of your Pod and restarts the Pod's Container if it terminates. Deployments are the recommended way to manage the creation and scaling of Pods.

1. Use the kubectl create command to create a Deployment that manages a Pod. The Pod runs a Container based on the provided Docker image.  
```
# Run a test container image that includes a webserver  
kubectl create deployment hello-node --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
```      
2. View the Deployment:
```
kubectl get deployments
```
The output is similar to:

|    NAME       |  READY |  UP-TO-DATE |  AVAILABLE |  AGE |
|---------------|--------|-------------|------------|------|
|    hello-node |  1/1   |  1          |  1         |  1m  |

3. View the Pod:  
```
kubectl get pods
```
The output is similar to:
|NAME                        |  READY  |   STATUS |   RESTARTS | AGE |
|----------------------------|---------|----------|------------|-----|
|hello-node-5f76cf6ccf-br9b5 |  1/1    |  Running | 0          | 1m  |

4. View cluster events:  
```
    kubectl get events
```
5. View the kubectl configuration:  
```
    kubectl config view
```
6. View application logs for a container in a pod (replace pod name with the one you got from kubectl get pods).
```    
    kubectl logs hello-node-5f76cf6ccf-br9b5
```
The output is similar to:
   | I0911 09:19:26.677397   |   1 log.go:195] Started HTTP server on port 8080  |
   |-------------------------|---------------------------------------------------|
   | I0911 09:19:26.677586   |   1 log.go:195] Started UDP server on port  8081  |
