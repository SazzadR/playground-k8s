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
