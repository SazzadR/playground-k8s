* Create the EKS cluster and the required resources.
```shell
terraform init
terraform apply
```

* Configure kubectl to connect to the EKS cluster.
```shell
aws eks update-kubeconfig --region $(terraform output -raw aws_region) --name $(terraform output -raw eks_cluster_name)
```

* Get the DNS name for the application.
```shell
kubectl get ingress -n k8s-demo-app
```

* Get the DNS name for ArgoCD UI.
```shell
kubectl get services -n argocd | grep argocd-server
```

[//]: # (```shell)

[//]: # (kubectl apply -f apps/k8s_demo_app.yaml)

[//]: # ()
[//]: # (kubectl apply -f values/load-balancer.yaml)

[//]: # (```)
