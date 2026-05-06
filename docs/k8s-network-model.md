# Services, Load Balancing, and Networking

## The Kubernetes network model
The Kubernetes network model is built out of several pieces:

- Each pod in a cluster gets its own unique cluster-wide IP address.
  - A pod has its own private network namespace which is shared by all of the containers within the pod. Processes running in different containers in the same pod can communicate with each other over localhost.
- The pod network (also called a cluster network) handles communication between pods. It ensures that (barring intentional network segmentation):
  - All pods can communicate with all other pods, whether they are on the same node or on different nodes. Pods can communicate with each other directly, without the use of proxies or address translation (NAT).  
    On Windows, this rule does not apply to host-network pods. 
  - Agents on a node (such as system daemons, or kubelet) can communicate with all pods on that node.
- The Service API lets you provide a stable (long lived) IP address or hostname for a service implemented by one or more backend pods, where the individual pods making up the service can change over time.
  - Kubernetes automatically manages EndpointSlice objects to provide information about the pods currently backing a Service. 
  - A service proxy implementation monitors the set of Service and EndpointSlice objects, and programs the data plane to route service traffic to its backends, by using operating system or cloud provider APIs to intercept or rewrite packets.
- The Gateway API (or its predecessor, Ingress) allows you to make Services accessible to clients that are outside the cluster.
  - A simpler, but less-configurable, mechanism for cluster ingress is available via the Service API's type: LoadBalancer, when using a supported Cloud Provider.
- NetworkPolicy is a built-in Kubernetes API that allows you to control traffic between pods, or between pods and the outside world.

