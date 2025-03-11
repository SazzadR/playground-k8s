```shell
aws eks update-kubeconfig --region $(terraform output -raw aws_region) --name $(terraform output -raw eks_cluster_name)
```

```shell
kubectl apply -f apps/k8s_demo_app.yaml

kubectl apply -f values/load-balancer.yaml
```
