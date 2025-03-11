module "eks" {
    source  = "terraform-aws-modules/eks/aws"
    version = "~> 20.0"

    cluster_name    = local.eks_cluster_name
    cluster_version = local.eks_version

    cluster_endpoint_public_access  = true
    cluster_endpoint_private_access = false

    vpc_id = aws_vpc.main.id
    subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id, aws_subnet.public_1.id, aws_subnet.public_2.id]

    cluster_compute_config = {
        enabled = true
        node_pools = []
    }

    enable_cluster_creator_admin_permissions = true
}

resource "aws_eks_access_entry" "eks_access_entry" {
    cluster_name  = module.eks.cluster_name
    principal_arn = module.eks.node_iam_role_arn
    type          = "EC2"
}

resource "aws_eks_access_policy_association" "eks_access_entry" {
    cluster_name  = module.eks.cluster_name
    policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy"
    principal_arn = module.eks.node_iam_role_arn

    access_scope {
        type = "cluster"
    }
}

resource "kubectl_manifest" "eks_node_class" {
    yaml_body = yamlencode({
        apiVersion = "eks.amazonaws.com/v1"
        kind       = "NodeClass"
        metadata = {
            name = "default"
        }
        spec = {
            role = module.eks.node_iam_role_name

            subnetSelectorTerms = [
                { id = aws_subnet.private_1.id },
                { id = aws_subnet.private_2.id }
            ]

            securityGroupSelectorTerms = [
                { id = module.eks.node_security_group_id }
            ]
        }
    })

    depends_on = [module.eks, aws_eks_access_entry.eks_access_entry, aws_eks_access_policy_association.eks_access_entry]
}

resource "kubectl_manifest" "eks_node_pools" {
    yaml_body = yamlencode({
        apiVersion = "karpenter.sh/v1"
        kind       = "NodePool"
        metadata = {
            name = "default"
        }
        spec = {
            template = {
                spec = {
                    nodeClassRef = {
                        group = "eks.amazonaws.com"
                        kind  = "NodeClass"
                        name  = "default"
                    }
                    requirements = [
                        {
                            key      = "karpenter.sh/capacity-type"
                            operator = "In"
                            values = ["on-demand"]
                        },
                        {
                            key      = "eks.amazonaws.com/instance-category"
                            operator = "In"
                            values = ["t"]
                        },
                        {
                            key      = "eks.amazonaws.com/instance-cpu"
                            operator = "In"
                            values = ["2"]
                        },
                        {
                            key      = "topology.kubernetes.io/zone"
                            operator = "In"
                            values = [local.availability_zone_1, local.availability_zone_2]
                        },
                        {
                            key      = "kubernetes.io/arch"
                            operator = "In"
                            values = ["amd64"]
                        }
                    ]
                }
            },
            limits = {
                cpu    = 4
                memory = "4Gi"
            }
        }
    })
}

resource "helm_release" "metrics_server" {
    name       = "metrics-server"
    repository = "https://kubernetes-sigs.github.io/metrics-server/"
    chart      = "metrics-server"
    namespace  = "kube-system"

    timeout = 600

    values = [
        file("${path.module}/values/metrics-server.yaml")
    ]
}

resource "kubectl_manifest" "k8s_demo_app_namespace" {
    yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
    name: k8s-demo-app
YAML

    depends_on = [module.eks]
}

resource "kubectl_manifest" "k8s_demo_app_deployment" {
    yaml_body = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
    name: k8s-demo-app-deployment
    namespace: k8s-demo-app
spec:
    selector:
        matchLabels:
            app: k8s-demo-app
    template:
        metadata:
            labels:
                app: k8s-demo-app
        spec:
            containers:
                -   name: k8s-demo-app
                    image: sazzadr/k8s-demo-app:1.0
                    ports:
                        -   name: http
                            containerPort: 5000
                    resources:
                        requests:
                            cpu: 100m
                            memory: 256Mi
                        limits:
                            cpu: 100m
                            memory: 256Mi
YAML

    depends_on = [kubectl_manifest.k8s_demo_app_namespace]
}

resource "kubectl_manifest" "k8s_demo_app_service" {
    yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
    name: k8s-demo-app-service
    namespace: k8s-demo-app
spec:
    selector:
        app: k8s-demo-app
    ports:
        -   name: http
            protocol: TCP
            port: 5000
            targetPort: 5000
YAML

    depends_on = [kubectl_manifest.k8s_demo_app_deployment]
}

resource "kubectl_manifest" "k8s_demo_app_hpa" {
    yaml_body = <<YAML
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
    name: k8s-demo-app-hpa
    namespace: k8s-demo-app
spec:
    scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: k8s-demo-app-deployment
    minReplicas: 2
    maxReplicas: 5
    metrics:
        -   type: Resource
            resource:
                name: cpu
                target:
                    type: Utilization
                    averageUtilization: 80
        -   type: Resource
            resource:
                name: memory
                target:
                    type: Utilization
                    averageUtilization: 70
YAML

    depends_on = [kubectl_manifest.k8s_demo_app_service]
}

resource "kubectl_manifest" "ingress_class_params" {
    yaml_body = <<YAML
apiVersion: eks.amazonaws.com/v1
kind: IngressClassParams
metadata:
    name: alb
spec:
    scheme: internet-facing
YAML

    depends_on = [kubectl_manifest.k8s_demo_app_hpa]
}

resource "kubectl_manifest" "ingress_class" {
    yaml_body = <<YAML
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
    name: alb
    annotations:
        ingressclass.kubernetes.io/is-default-class: "true"
spec:
    # Configures the IngressClass to use EKS Auto Mode
    controller: eks.amazonaws.com/alb
    parameters:
        apiGroup: eks.amazonaws.com
        kind: IngressClassParams
        name: alb
YAML

    depends_on = [kubectl_manifest.ingress_class_params]
}

resource "kubectl_manifest" "ingress" {
    yaml_body = <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
    name: k8s-demo-app
    namespace: k8s-demo-app
spec:
    ingressClassName: alb
    rules:
        -   http:
                paths:
                    -   path: /*
                        pathType: ImplementationSpecific
                        backend:
                            service:
                                name: k8s-demo-app-service
                                port:
                                    number: 5000
YAML

    depends_on = [kubectl_manifest.ingress_class]
}
